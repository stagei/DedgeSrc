CREATE TABLE ActionCodes (
    ActionCode VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (ActionCode)
);

CREATE TABLE AdverseEvents (
    EventID INTEGER,
    TrialID INTEGER NOT NULL,
    EventType VARCHAR(255) NOT NULL,
    EventDate TIMESTAMP NOT NULL,
    DetectedDate TIMESTAMP NOT NULL,
    ReportDate TIMESTAMP NOT NULL,
    PatientID INTEGER NOT NULL,
    EventDescription VARCHAR(255) NOT NULL,
    Severity VARCHAR(255) NOT NULL,
    Seriousness VARCHAR(255) NOT NULL,
    Causality VARCHAR(255) NOT NULL,
    Outcome VARCHAR(255) NOT NULL,
    ActionTaken VARCHAR(255) NOT NULL,
    ReportedToRegionalEthicsCommittee BOOLEAN NOT NULL,
    RegionalEthicsCommitteeReportDate TIMESTAMP NOT NULL,
    ReportedToSLV BOOLEAN NOT NULL,
    SLVReportDate TIMESTAMP NOT NULL,
    ReportedToSponsor BOOLEAN NOT NULL,
    SponsorReportDate TIMESTAMP NOT NULL,
    FollowUpRequired BOOLEAN NOT NULL,
    StatusDescription VARCHAR(255) NOT NULL,
    ClosedDate TIMESTAMP NOT NULL,
    ClosedByTrialPersonnelID INTEGER NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (EventID)
);

CREATE TABLE Authorities (
    AuthorityID INTEGER,
    AuthorityType VARCHAR(255) NOT NULL,
    LegislationCountryCode VARCHAR(255) NOT NULL,
    OrganizationID INTEGER NOT NULL,
    LongName VARCHAR(255) NOT NULL,
    AbbriviationName VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (AuthorityID)
);

CREATE TABLE AuthorityPersonnel (
    AuthorityPersonnelID INTEGER,
    AuthorityID INTEGER NOT NULL,
    PersonID INTEGER NOT NULL,
    StartDate TIMESTAMP NOT NULL,
    EndDate TIMESTAMP NOT NULL,
    Specialization VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (AuthorityPersonnelID)
);

CREATE TABLE AuthoritySteps (
    AuthorityStepID INTEGER,
    AuthorityID INTEGER NOT NULL,
    OrderIndex INTEGER NOT NULL,
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    WindowBeforeDays INTEGER NOT NULL,
    WindowAfterDays INTEGER NOT NULL,
    Required BOOLEAN NOT NULL,
    Instructions VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (AuthorityStepID)
);

CREATE TABLE AuthorityTypes (
    AuthorityType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (AuthorityType)
);

CREATE TABLE CountryCodes (
    CountryCode VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    PhoneCountryCode VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (CountryCode)
);

CREATE TABLE DeviationTypes (
    DeviationType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (DeviationType)
);

CREATE TABLE Documents (
    DocumentID INTEGER,
    TrialID INTEGER NOT NULL,
    DocumentType VARCHAR(255) NOT NULL,
    DocumentName VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    Version VARCHAR(255) NOT NULL,
    DocumentDate TIMESTAMP NOT NULL,
    ApprovedDate TIMESTAMP NOT NULL,
    ApprovedBySponsorPersonnelID INTEGER NOT NULL,
    ApprovedByHospitalPersonnelID INTEGER NOT NULL,
    DocumentLocation VARCHAR(255) NOT NULL,
    FilePath VARCHAR(255) NOT NULL,
    FileFormat VARCHAR(255) NOT NULL,
    Status VARCHAR(255) NOT NULL,
    IsCurrent BOOLEAN NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (DocumentID)
);

CREATE TABLE DocumentTypes (
    DocumentType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (DocumentType)
);

CREATE TABLE EventTypes (
    EventType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (EventType)
);

CREATE TABLE HospitalPersonnel (
    HospitalPersonnelID INTEGER,
    HospitalID INTEGER NOT NULL,
    PersonID INTEGER NOT NULL,
    StartDate TIMESTAMP NOT NULL,
    EndDate TIMESTAMP NOT NULL,
    Specialization VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    UserAccessType VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (HospitalPersonnelID)
);

CREATE TABLE Hospitals (
    HospitalID INTEGER,
    OrganizationID INTEGER NOT NULL,
    LegislativeCountryCode VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (HospitalID)
);

CREATE TABLE InspectionLogs (
    InspectionLogID INTEGER,
    InspectionID INTEGER NOT NULL,
    Findings VARCHAR(255) NOT NULL,
    IsCritical BOOLEAN NOT NULL,
    IsFollowUpRequired BOOLEAN NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (InspectionLogID)
);

CREATE TABLE Inspections (
    InspectionID INTEGER,
    TrialID INTEGER NOT NULL,
    InspectionType VARCHAR(255) NOT NULL,
    InspectionDate TIMESTAMP NOT NULL,
    SponsorTrialRoleID INTEGER NOT NULL,
    TrialPersonnelID INTEGER NOT NULL,
    EstimatedStartDateTime TIMESTAMP NOT NULL,
    EstimatedEndDateTime TIMESTAMP NOT NULL,
    ActualStartDateTime TIMESTAMP NOT NULL,
    ActualEndDateTime TIMESTAMP NOT NULL,
    PlannedDuration DOUBLE PRECISION NOT NULL,
    ActualDuration DOUBLE PRECISION NOT NULL,
    FindingsCount INTEGER NOT NULL,
    MajorFindings INTEGER NOT NULL,
    MinorFindings INTEGER NOT NULL,
    CriticalFindings INTEGER NOT NULL,
    FollowUpRequired BOOLEAN NOT NULL,
    FollowUpDate TIMESTAMP NOT NULL,
    FollowUpCompleted BOOLEAN NOT NULL,
    ReportReceived BOOLEAN NOT NULL,
    ReportDate TIMESTAMP NOT NULL,
    ReportLocation VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (InspectionID)
);

CREATE TABLE InspectionTypes (
    InspectionType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (InspectionType)
);

CREATE TABLE Milestones (
    MilestoneID INTEGER,
    TrialID INTEGER NOT NULL,
    MilestoneName VARCHAR(255) NOT NULL,
    MilestoneType VARCHAR(255) NOT NULL,
    PlannedDate TIMESTAMP NOT NULL,
    ActualDate TIMESTAMP NOT NULL,
    Status VARCHAR(255) NOT NULL,
    InvolvesAuthorityID INTEGER NOT NULL,
    ResponsibleTrialRoleID INTEGER NOT NULL,
    Critical BOOLEAN NOT NULL,
    Completed BOOLEAN NOT NULL,
    TransitionPhaseCode VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (MilestoneID)
);

CREATE TABLE MilestoneSteps (
    MilestoneStepID INTEGER,
    MilestoneID INTEGER NOT NULL,
    ActionCode VARCHAR(255) NOT NULL,
    AuthorityStepID INTEGER NOT NULL,
    TrialRoleID INTEGER NOT NULL,
    ReferenceNumber VARCHAR(255) NOT NULL,
    SubmittedDate TIMESTAMP NOT NULL,
    ApprovedDate TIMESTAMP NOT NULL,
    ExpiryDate TIMESTAMP NOT NULL,
    DocumentationLocation VARCHAR(255) NOT NULL,
    Status VARCHAR(255) NOT NULL,
    Version VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (MilestoneStepID)
);

CREATE TABLE MilestoneTypes (
    MilestoneType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (MilestoneType)
);

CREATE TABLE OrganizationDepartments (
    OrganizationDepartmentID INTEGER,
    OrganizationID INTEGER NOT NULL,
    DepartmentName VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (OrganizationDepartmentID)
);

CREATE TABLE Organizations (
    OrganizationID INTEGER,
    OrganizationNumber VARCHAR(255) NOT NULL,
    OrganizationName VARCHAR(255) NOT NULL,
    CountryCode VARCHAR(255) NOT NULL,
    Address VARCHAR(255) NOT NULL,
    PostalCode VARCHAR(255) NOT NULL,
    City VARCHAR(255) NOT NULL,
    Phone VARCHAR(255) NOT NULL,
    Email VARCHAR(255) NOT NULL,
    Website VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (OrganizationID)
);

CREATE TABLE PatientSchedules (
    PatientScheduleID INTEGER,
    TrialID INTEGER NOT NULL,
    Description VARCHAR(255) NOT NULL,
    Name VARCHAR(255) NOT NULL,
    OffsetDays INTEGER NOT NULL,
    WindowBeforeDays INTEGER NOT NULL,
    WindowAfterDays INTEGER NOT NULL,
    AffectedByProtocolID INTEGER NOT NULL,
    Required BOOLEAN NOT NULL,
    Instructions VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (PatientScheduleID)
);

CREATE TABLE Persons (
    PersonID INTEGER,
    FirstName VARCHAR(255) NOT NULL,
    LastName VARCHAR(255) NOT NULL,
    Title VARCHAR(255) NOT NULL,
    CountryCode VARCHAR(255) NOT NULL,
    Phone VARCHAR(255) NOT NULL,
    Mobile VARCHAR(255) NOT NULL,
    Email VARCHAR(255) NOT NULL,
    Gender VARCHAR(255) NOT NULL,
    BirthDate VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (PersonID)
);

CREATE TABLE PhaseCodes (
    PhaseCode VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (PhaseCode)
);

CREATE TABLE Protocols (
    ProtocolID INTEGER,
    TrialID INTEGER NOT NULL,
    ProtocolReference VARCHAR(255) NOT NULL,
    EffectiveDate TIMESTAMP NOT NULL,
    ValidFromDate TIMESTAMP NOT NULL,
    ValidToDate TIMESTAMP NOT NULL,
    ProtocolDescription VARCHAR(255) NOT NULL,
    DocumentID INTEGER NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (ProtocolID)
);

CREATE TABLE QualityManagementReviews (
    QualityManagementReviewID INTEGER,
    TrialID INTEGER NOT NULL,
    ActivityType VARCHAR(255) NOT NULL,
    ActivityDate TIMESTAMP NOT NULL,
    PerformedByTrialPersonnelID INTEGER NOT NULL,
    Scope VARCHAR(255) NOT NULL,
    Findings VARCHAR(255) NOT NULL,
    Recommendations VARCHAR(255) NOT NULL,
    ActionsRequired VARCHAR(255) NOT NULL,
    ActionDueDate TIMESTAMP NOT NULL,
    ActionCompletedDate TIMESTAMP NOT NULL,
    ReportLocationDescription VARCHAR(255) NOT NULL,
    ReportDocumentID INTEGER NOT NULL,
    IsResolved BOOLEAN NOT NULL,
    ResolvedByTrialPersonnelID INTEGER NOT NULL,
    ResolvedDate TIMESTAMP NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (QualityManagementReviewID)
);

CREATE TABLE RoleTypes (
    RoleType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (RoleType)
);

CREATE TABLE SponsorPersonnel (
    SponsorPersonnelID INTEGER,
    SponsorID INTEGER NOT NULL,
    PersonID INTEGER NOT NULL,
    StartDate TIMESTAMP NOT NULL,
    EndDate TIMESTAMP NOT NULL,
    Specialization VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (SponsorPersonnelID)
);

CREATE TABLE Sponsors (
    SponsorID INTEGER,
    OrganizationID INTEGER NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (SponsorID)
);

CREATE TABLE SystemFieldNameMappings (
    Name VARCHAR(255),
    TranslationValue VARCHAR(255) NOT NULL,
    LanguageCode VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (Name)
);

CREATE TABLE SystemLogs (
    UserName VARCHAR(255) NOT NULL,
    FormName VARCHAR(255) NOT NULL,
    ControlName VARCHAR(255) NOT NULL,
    Severity VARCHAR(255) NOT NULL,
    LogMessage VARCHAR(255) NOT NULL,
    LogData VARCHAR(255) NOT NULL,
    LogDateTime TIMESTAMP NOT NULL DEFAULT NOW
);

CREATE TABLE SystemTableNameMappings (
    Name VARCHAR(255),
    TranslationValue VARCHAR(255) NOT NULL,
    LanguageCode VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (Name)
);

CREATE TABLE TrialDeviations (
    DeviationID INTEGER,
    TrialID INTEGER NOT NULL,
    DeviationDate TIMESTAMP NOT NULL,
    DetectedDate TIMESTAMP NOT NULL,
    DeviationType VARCHAR(255) NOT NULL,
    Severity VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    ImmediateAction VARCHAR(255) NOT NULL,
    RootCause VARCHAR(255) NOT NULL,
    CAPA VARCHAR(255) NOT NULL,
    CAPADueDate TIMESTAMP NOT NULL,
    CAPACompletedDate TIMESTAMP NOT NULL,
    ReportedToRegionalEthicsCommittee BOOLEAN NOT NULL,
    RegionalEthicsCommitteeReportDate TIMESTAMP NOT NULL,
    ReportedToSponsor BOOLEAN NOT NULL,
    SponsorReportDate TIMESTAMP NOT NULL,
    ResponsibleTrialRoleID INTEGER NOT NULL,
    Status VARCHAR(255) NOT NULL,
    ClosedDate TIMESTAMP NOT NULL,
    ClosedByTrialPersonnelID INTEGER NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (DeviationID)
);

CREATE TABLE TrialPatients (
    PatientID INTEGER,
    TrialID INTEGER NOT NULL,
    PatientCode VARCHAR(255) NOT NULL,
    ScreeningDate TIMESTAMP NOT NULL,
    EnrollmentDate TIMESTAMP NOT NULL,
    ApprovalDate TIMESTAMP NOT NULL,
    CompletionDate TIMESTAMP NOT NULL,
    WithdrawalDate TIMESTAMP NOT NULL,
    PatientStatus VARCHAR(255) NOT NULL,
    DisqualificationReason VARCHAR(255) NOT NULL,
    AgeAtScreening INTEGER NOT NULL,
    Gender VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (PatientID)
);

CREATE TABLE TrialPersonnel (
    TrialPersonnelID INTEGER,
    TrialID INTEGER NOT NULL,
    TrialPersonnelType VARCHAR(255) NOT NULL,
    HospitalPersonnelID INTEGER NOT NULL,
    SponsorPersonnelID INTEGER NOT NULL,
    AuthorityPersonnelID INTEGER NOT NULL,
    IsPrimary BOOLEAN NOT NULL,
    StartDate TIMESTAMP NOT NULL,
    EndDate TIMESTAMP NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (TrialPersonnelID)
);

CREATE TABLE TrialPersonnelTypes (
    TrialPersonnelType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (TrialPersonnelType)
);

CREATE TABLE TrialRoles (
    TrialRoleID INTEGER,
    TrialID INTEGER NOT NULL,
    TrialPersonnelID INTEGER NOT NULL,
    RoleType VARCHAR(255) NOT NULL,
    IsPrimary BOOLEAN NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (TrialRoleID)
);

CREATE TABLE Trials (
    TrialID INTEGER,
    HospitalID INTEGER NOT NULL,
    SponsorID INTEGER NOT NULL,
    TrialType VARCHAR(255) NOT NULL,
    TrialTitle VARCHAR(255) NOT NULL,
    Indication VARCHAR(255) NOT NULL,
    EudraCTNumber VARCHAR(255) NOT NULL,
    ClinicalTrialsGovID VARCHAR(255) NOT NULL,
    PlannedEnrollment INTEGER NOT NULL,
    ActualEnrollment INTEGER NOT NULL,
    NumberScreened INTEGER NOT NULL,
    NumberIncluded INTEGER NOT NULL,
    PlannedStartDate TIMESTAMP NOT NULL,
    FirstPatientInDate TIMESTAMP NOT NULL,
    LastPatientOutDate TIMESTAMP NOT NULL,
    DatabaseLockDate TIMESTAMP NOT NULL,
    ReportSentDate TIMESTAMP NOT NULL,
    ArchivingDate TIMESTAMP NOT NULL,
    OverallStatus VARCHAR(255) NOT NULL,
    ProtocolVersion VARCHAR(255) NOT NULL,
    CurrentProtocolID INTEGER NOT NULL,
    CurrentPhaseCode VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (TrialID)
);

CREATE TABLE TrialTypes (
    TrialType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    Instructions VARCHAR(255) NOT NULL,
    Notes VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (TrialType)
);

CREATE TABLE UserAccessTypes (
    UserAccessType VARCHAR(255),
    Name VARCHAR(255) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    CreatedDate TIMESTAMP NOT NULL,
    ModifiedDate TIMESTAMP NOT NULL,
    CreatedBy VARCHAR(255) NOT NULL,
    ModifiedBy VARCHAR(255) NOT NULL,
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (UserAccessType)
);