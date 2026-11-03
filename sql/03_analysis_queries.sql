/*
================================================================================
 DW_query.sql
================================================================================
 Six analytical queries across library operations.
================================================================================
*/

USE library_dw;

-- ------------------------------------------------------------------
-- Analysis 1: Are loan transactions higher on weekends than weekdays?
-- Dimension: Time
-- Compares average loans PER DAY (not raw totals) across each day of
-- the week, so the comparison is fair despite weekdays occurring more
-- often than weekend days over the full date range.
-- ------------------------------------------------------------------
SELECT
    t.DayName,
    t.IsWeekend,
    COUNT(*) AS TotalLoans,
    COUNT(DISTINCT t.FullDate) AS DaysObserved,
    ROUND(COUNT(*) / COUNT(DISTINCT t.FullDate), 1) AS AvgLoansPerDay
FROM LoanFact f
JOIN TimeDim t ON f.TimeKey = t.TimeKey
GROUP BY t.DayName, t.IsWeekend, t.DayOfWeek
ORDER BY t.DayOfWeek;


-- ------------------------------------------------------------------
-- Analysis 2: Do members of higher membership tiers borrow more books
-- on average than members of lower tiers?
-- Dimension: MemberDim using TierName and TierLevel
-- Compares average loans PER MEMBER (not raw totals) across tiers, so
-- the comparison is fair despite each tier having a different number
-- of members.
-- ------------------------------------------------------------------
SELECT
    m.TierName,
    m.TierLevel,
    COUNT(DISTINCT m.MemberKey) AS TotalMembers,
    COUNT(*) AS TotalLoans,
    ROUND(COUNT(*) / COUNT(DISTINCT m.MemberKey), 1) AS AvgLoansPerMember
FROM LoanFact f
JOIN MemberDim m ON f.MemberKey = m.MemberKey
GROUP BY m.TierName, m.TierLevel
ORDER BY m.TierLevel;


-- ------------------------------------------------------------------
-- Analysis 3:
-- Which ten books recorded the highest number of completed loans?
-- Dimension: BookCopy
-- BookID is used to combine transactions across all physical copies
-- belonging to the same book.
-- ------------------------------------------------------------------
SELECT
    b.BookID,
    b.Title,
    b.Author,
    b.Genre,
    COUNT(*) AS CompletedLoans
FROM LoanFact f
JOIN BookCopyDim b
    ON f.BookCopyKey = b.BookCopyKey
GROUP BY
    b.BookID,
    b.Title,
    b.Author,
    b.Genre
ORDER BY
    CompletedLoans DESC,
    b.Title
LIMIT 10;

-- ------------------------------------------------------------------
-- Analysis 4:
-- Which staff departments and employment types handled the highest
-- completed-loan volume and workload per staff member?
-- Dimension: StaffDim using Department and EmploymentType
-- ------------------------------------------------------------------
SELECT
    s.Department,
    s.EmploymentType,
    COUNT(*) AS CompletedLoans,
    COUNT(DISTINCT s.StaffKey) AS StaffCount,
    ROUND(
        COUNT(*) / COUNT(DISTINCT s.StaffKey),
        2
    ) AS AvgLoansPerStaff
FROM LoanFact f
JOIN StaffDim s
    ON f.StaffKey = s.StaffKey
GROUP BY
    s.Department,
    s.EmploymentType
ORDER BY
    CompletedLoans DESC,
    AvgLoansPerStaff DESC;

-- ------------------------------------------------------------------
-- Analysis 5:
-- Which book genres have the longest average loan duration and
-- highest late-return rate?
-- Dimension: BookCopy Genre
-- Measures: average duration, late loans and late-return rate
-- ------------------------------------------------------------------
SELECT
    b.Genre,
    COUNT(*) AS CompletedLoans,
    ROUND(AVG(f.LoanDurationDays), 2) AS AvgLoanDurationDays,
    SUM(
        IF(f.DaysLate > 0, 1, 0)
    ) AS LateLoans,
    ROUND(
        SUM(IF(f.DaysLate > 0, 1, 0))
        / COUNT(*) * 100,
        2
    ) AS LateReturnRate
FROM LoanFact f
JOIN BookCopyDim b
    ON f.BookCopyKey = b.BookCopyKey
GROUP BY
    b.Genre
ORDER BY
    AvgLoanDurationDays DESC,
    LateReturnRate DESC;

-- ------------------------------------------------------------------
-- Analysis 6:
-- What are the top three most popular genres for each membership tier?
-- Dimensions: MemberDim and BookCopyDim
-- RANK() separately ranks genres within each membership tier.
-- ------------------------------------------------------------------
WITH GenreLoanCount AS (
    SELECT
        m.TierName,
        m.TierLevel,
        b.Genre,
        COUNT(*) AS CompletedLoans
    FROM LoanFact f
    JOIN MemberDim m
        ON f.MemberKey = m.MemberKey
    JOIN BookCopyDim b
        ON f.BookCopyKey = b.BookCopyKey
    GROUP BY
        m.TierName,
        m.TierLevel,
        b.Genre
),
RankedGenre AS (
    SELECT
        TierName,
        TierLevel,
        Genre,
        CompletedLoans,
        RANK() OVER (
            PARTITION BY TierName, TierLevel
            ORDER BY CompletedLoans DESC
        ) AS GenreRank
    FROM GenreLoanCount
)
SELECT
    TierName,
    TierLevel,
    GenreRank,
    Genre,
    CompletedLoans
FROM RankedGenre
WHERE GenreRank <= 3
ORDER BY
    TierLevel,
    GenreRank,
    Genre;
