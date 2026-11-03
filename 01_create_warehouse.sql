/*
================================================================================
 DW_create.sql
================================================================================
 Star schema data warehouse for a fictional library.

 Design notes:
   - Fact table: LoanFact, grain = one row per loan transaction.
   - 4 dimensions: TimeDim, MemberDim, StaffDim, BookCopyDim.
   - Single TimeKey link (loan start date); ReturnDate is a plain
     column, not a second dimension key.
   - TierID/MinTierID excluded from MemberDim/BookCopyDim - TierName +
     active vs completed loans identified via ReturnDate IS NULL.
   - Surrogate keys are plain INT (no AUTO_INCREMENT), matching
   - No SCD implemented (not required).

================================================================================
*/

CREATE DATABASE IF NOT EXISTS library_dw;
USE library_dw;

-- ------------------------------------------------------------------
-- TimeDim: day-level granularity
-- ------------------------------------------------------------------
CREATE TABLE TimeDim (
    TimeKey INT PRIMARY KEY,
    FullDate DATE NOT NULL,
    DayName VARCHAR(10) NOT NULL,
    DayOfWeek INT NOT NULL,        -- 1 = Monday ... 7 = Sunday
    DayOfMonth INT NOT NULL,
    IsWeekend TINYINT(1) NOT NULL,
    MonthName VARCHAR(10) NOT NULL,
    MonthNumber INT NOT NULL,
    Quarter INT NOT NULL,
    Year INT NOT NULL
);

-- ------------------------------------------------------------------
-- MemberDim: tier attributes denormalised in (star schema)
-- ------------------------------------------------------------------
CREATE TABLE MemberDim (
    MemberKey INT PRIMARY KEY,
    MemberID CHAR(10) NOT NULL,
    Name VARCHAR(100) NOT NULL,
    Gender CHAR(1) NOT NULL,
    DOB DATE NOT NULL,
    Occupation VARCHAR(50) NULL,
    RegistrationDate DATE NOT NULL,
    TierName VARCHAR(20) NOT NULL,
    TierLevel INT NOT NULL,
    BorrowLimit INT NOT NULL
);

-- ------------------------------------------------------------------
-- StaffDim
-- ------------------------------------------------------------------
CREATE TABLE StaffDim (
    StaffKey INT PRIMARY KEY,
    StaffID CHAR(10) NOT NULL,
    Name VARCHAR(100) NOT NULL,
    Gender CHAR(1) NOT NULL,
    EmploymentType VARCHAR(20) NOT NULL,
    StartDate DATE NOT NULL,
    Department VARCHAR(50) NOT NULL
);

-- ------------------------------------------------------------------
-- BookCopyDim: copy-level grain
-- ------------------------------------------------------------------
CREATE TABLE BookCopyDim (
    BookCopyKey INT PRIMARY KEY,
    BookID CHAR(10) NOT NULL,
    CopySeqNo INT NOT NULL,
    Title VARCHAR(200) NOT NULL,
    Author VARCHAR(100) NOT NULL,
    Genre VARCHAR(50) NOT NULL,
    MinTierName VARCHAR(20) NOT NULL,
    MinTierLevel INT NOT NULL
);

-- ------------------------------------------------------------------
-- LoanFact
--   LoanDurationDays: NULL while active; DaysLate: 0 if on-time/active,
--   positive integer if late. Late loans can be found directly via
--   WHERE DaysLate > 0 - no separate IsLate flag needed, since
--   DaysLate is NOT NULL and fully derivable to the same result.
--   Active vs completed identified via ReturnDate IS NULL (no separate
--   LoanFact contains completed loans only.
--   ReturnDate and LoanDurationDays are therefore always available
--   for every loaded fact row.
-- ------------------------------------------------------------------
CREATE TABLE LoanFact (
    LoanKey INT PRIMARY KEY,
    MemberKey INT NOT NULL,
    TimeKey INT NOT NULL,
    StaffKey INT NOT NULL,
    BookCopyKey INT NOT NULL,
    ReturnDate DATE NULL,
    LoanDurationDays INT NULL,
    DaysLate INT NOT NULL,
    FOREIGN KEY (MemberKey) REFERENCES MemberDim(MemberKey),
    FOREIGN KEY (TimeKey) REFERENCES TimeDim(TimeKey),
    FOREIGN KEY (StaffKey) REFERENCES StaffDim(StaffKey),
    FOREIGN KEY (BookCopyKey) REFERENCES BookCopyDim(BookCopyKey)
);
