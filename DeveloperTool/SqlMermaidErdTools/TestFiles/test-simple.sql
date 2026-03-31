-- Simple test with a few tables

CREATE TABLE ActionCodes (
    ActionCode NVARCHAR(50),
    Name NVARCHAR(50),
    Description NVARCHAR(500),
    PRIMARY KEY (ActionCode)
);

CREATE TABLE AdverseEvents (
    EventID INT,
    TrialID INT,
    EventType NVARCHAR(50),
    EventDate DATETIME,
    PatientID INT,
    EventDescription NVARCHAR(500),
    Severity NVARCHAR(50),
    PRIMARY KEY (EventID)
);

CREATE TABLE Trials (
    TrialID INT,
    TrialNumber NVARCHAR(50),
    TrialTitle NVARCHAR(200),
    ProtocolID INT,
    SponsorID INT,
    StartDate DATETIME,
    EndDate DATETIME,
    PRIMARY KEY (TrialID),
    FOREIGN KEY (ProtocolID) REFERENCES Protocols(ProtocolID)
);

CREATE TABLE Protocols (
    ProtocolID INT,
    ProtocolNumber NVARCHAR(50),
    Version NVARCHAR(20),
    Title NVARCHAR(200),
    PRIMARY KEY (ProtocolID)
);

