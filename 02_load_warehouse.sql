/*
================================================================================
 DW_insert.sql
================================================================================
 Extracts and loads data from the OLTP database (library_oltp) into the DW
 (library_dw) using SQL that reads directly from the OLTP tables via JOIN.

 Requires pre-existing and populated library_oltp source tables.
 Run after 01_create_warehouse.sql.

 Confirmed ETL decisions:
   - T9999 SuperAdmin remains in the OLTP MembershipTier table because
     it is part of the provided source data.
   - T9999 is excluded from the DW because no real member or book uses it.
   - Active loans remain in OLTP and are excluded from LoanFact.
   - Only completed loans, where ReturnDatetime IS NOT NULL, are loaded
     into the DW for historical analysis.
   - TimeDim is sparse and is generated from completed loan start dates.
   - TierID/MinTierID are not selected into MemberDim/BookCopyDim.
   - LoanFact has no IsReturned, IsLost, LoanCount, DueDate, or IsLate
     columns. A late loan can be identified using DaysLate > 0.

 Load order:
   1. TimeDim
   2. MemberDim
   3. StaffDim
   4. BookCopyDim
   5. LoanFact
================================================================================
*/

USE library_dw;

-- ------------------------------------------------------------------
-- 1) TimeDim: dates used by completed loan transactions only.
-- ------------------------------------------------------------------
INSERT INTO TimeDim (
    TimeKey, FullDate, DayName, DayOfWeek, DayOfMonth, IsWeekend,
    MonthName, MonthNumber, Quarter, Year
)
SELECT
    ROW_NUMBER() OVER (ORDER BY d.FullDate) AS TimeKey,
    d.FullDate,
    DAYNAME(d.FullDate),
    WEEKDAY(d.FullDate) + 1,
    DAY(d.FullDate),
    IF(WEEKDAY(d.FullDate) >= 5, 1, 0),
    MONTHNAME(d.FullDate),
    MONTH(d.FullDate),
    QUARTER(d.FullDate),
    YEAR(d.FullDate)
FROM (
    SELECT DISTINCT DATE(StartDatetime) AS FullDate
    FROM library_oltp.Loan
    WHERE ReturnDatetime IS NOT NULL
) d;

-- ------------------------------------------------------------------
-- 2) MemberDim: T9999 is explicitly excluded from the DW.
--    The source data currently has no member assigned to T9999, so
--    the expected row count remains 301.
-- ------------------------------------------------------------------
INSERT INTO MemberDim (
    MemberKey, MemberID, Name, Gender, DOB, Occupation,
    RegistrationDate, TierName, TierLevel, BorrowLimit
)
SELECT
    ROW_NUMBER() OVER (ORDER BY m.MemberID),
    m.MemberID,
    m.Name,
    m.Gender,
    m.DOB,
    m.Occupation,
    DATE(m.RegistrationDatetime),
    t.TierName,
    t.TierLevel,
    t.BorrowLimit
FROM library_oltp.Member m
JOIN library_oltp.MembershipTier t
    ON m.TierID = t.TierID
WHERE t.TierID <> 'T9999';

-- ------------------------------------------------------------------
-- 3) StaffDim
-- ------------------------------------------------------------------
INSERT INTO StaffDim (
    StaffKey, StaffID, Name, Gender, EmploymentType, Department, StartDate
)
SELECT
    ROW_NUMBER() OVER (ORDER BY StaffID),
    StaffID,
    Name,
    Gender,
    EmploymentType,
    Department,
    StartDate
FROM library_oltp.Staff;

-- ------------------------------------------------------------------
-- 4) BookCopyDim: T9999 is explicitly excluded from the DW.
--    The source data currently has no book assigned to T9999, so
--    the expected row count remains 1265.
-- ------------------------------------------------------------------
INSERT INTO BookCopyDim (
    BookCopyKey, BookID, CopySeqNo, Title, Author, Genre,
    MinTierName, MinTierLevel
)
SELECT
    ROW_NUMBER() OVER (ORDER BY bc.BookID, bc.CopySeqNo),
    bc.BookID,
    bc.CopySeqNo,
    b.Title,
    b.Author,
    b.Genre,
    t.TierName,
    t.TierLevel
FROM library_oltp.BookCopy bc
JOIN library_oltp.Book b
    ON bc.BookID = b.BookID
JOIN library_oltp.MembershipTier t
    ON b.MinTierID = t.TierID
WHERE t.TierID <> 'T9999';

-- ------------------------------------------------------------------
-- 5) LoanFact: completed loans only.
--    The one active loan with ReturnDatetime IS NULL stays in OLTP.
--    Expected LoanFact row count: 12343 instead of 12344.
-- ------------------------------------------------------------------
INSERT INTO LoanFact (
    LoanKey, MemberKey, TimeKey, StaffKey, BookCopyKey,
    ReturnDate, LoanDurationDays, DaysLate
)
SELECT
    ROW_NUMBER() OVER (
        ORDER BY l.StartDatetime, l.MemberID, l.BookID, l.CopySeqNo
    ),
    md.MemberKey,
    td.TimeKey,
    sd.StaffKey,
    bcd.BookCopyKey,
    DATE(l.ReturnDatetime),
    DATEDIFF(l.ReturnDatetime, l.StartDatetime),
    IF(
        DATE(l.ReturnDatetime) > l.DueDate,
        DATEDIFF(DATE(l.ReturnDatetime), l.DueDate),
        0
    )
FROM library_oltp.Loan l
JOIN MemberDim md
    ON l.MemberID = md.MemberID
JOIN BookCopyDim bcd
    ON l.BookID = bcd.BookID
   AND l.CopySeqNo = bcd.CopySeqNo
JOIN StaffDim sd
    ON l.StaffID = sd.StaffID
JOIN TimeDim td
    ON td.FullDate = DATE(l.StartDatetime)
WHERE l.ReturnDatetime IS NOT NULL;

-- ------------------------------------------------------------------
-- Verification 1: DW row counts
-- ------------------------------------------------------------------
SELECT 'TimeDim' AS TableName, COUNT(*) AS RowCount FROM TimeDim
UNION ALL SELECT 'MemberDim', COUNT(*) FROM MemberDim
UNION ALL SELECT 'StaffDim', COUNT(*) FROM StaffDim
UNION ALL SELECT 'BookCopyDim', COUNT(*) FROM BookCopyDim
UNION ALL SELECT 'LoanFact', COUNT(*) FROM LoanFact;

-- ------------------------------------------------------------------
-- Verification 2: active loan excluded and all fact FKs valid
-- Expected:
--   OLTP_Loan_Rows       = 12344
--   DW_LoanFact_Rows     = 12343
--   ExcludedActiveLoans  = 1
--   ActiveLoansInDW      = 0
--   NullFKs              = 0
-- ------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM library_oltp.Loan) AS OLTP_Loan_Rows,
    (SELECT COUNT(*) FROM LoanFact) AS DW_LoanFact_Rows,
    (SELECT COUNT(*) FROM library_oltp.Loan WHERE ReturnDatetime IS NULL)
        AS ExcludedActiveLoans,
    (SELECT COUNT(*) FROM LoanFact WHERE ReturnDate IS NULL)
        AS ActiveLoansInDW,
    (SELECT COUNT(*) FROM LoanFact WHERE DaysLate > 0)
        AS LateLoans,
    (SELECT COUNT(*)
     FROM LoanFact
     WHERE MemberKey IS NULL
        OR BookCopyKey IS NULL
        OR StaffKey IS NULL
        OR TimeKey IS NULL) AS NullFKs;

-- ------------------------------------------------------------------
-- Verification 3: T9999 exists in OLTP but not in the DW dimensions
-- Expected:
--   T9999_In_OLTP             = 1
--   SuperAdmin_In_MemberDim   = 0
--   SuperAdmin_In_BookCopyDim = 0
-- ------------------------------------------------------------------
SELECT
    (SELECT COUNT(*)
     FROM library_oltp.MembershipTier
     WHERE TierID = 'T9999') AS T9999_In_OLTP,
    (SELECT COUNT(*)
     FROM MemberDim
     WHERE TierName = 'SuperAdmin') AS SuperAdmin_In_MemberDim,
    (SELECT COUNT(*)
     FROM BookCopyDim
     WHERE MinTierName = 'SuperAdmin') AS SuperAdmin_In_BookCopyDim;