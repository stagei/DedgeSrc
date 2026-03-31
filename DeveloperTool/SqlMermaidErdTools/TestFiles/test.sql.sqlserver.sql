/* ============================================ */ /* MS Access Database Export */ /* Database: D:\opt\src\Misc\ClinicalStudiesSystem\MedTrailDb.accdb */ /* Generated: 2025-11-30 19:08:17 */ /* ============================================ */ /* ============================================ */ /* DROP TABLES */ /* ============================================ */
DROP TABLE IF EXISTS UserAccessTypes

DROP TABLE IF EXISTS TrialTypes

DROP TABLE IF EXISTS Trials

DROP TABLE IF EXISTS TrialRoles

DROP TABLE IF EXISTS TrialPersonnelTypes

DROP TABLE IF EXISTS TrialPersonnel

DROP TABLE IF EXISTS TrialPatients

DROP TABLE IF EXISTS TrialDeviations

DROP TABLE IF EXISTS SystemTableNameMappings

DROP TABLE IF EXISTS SystemLogs

DROP TABLE IF EXISTS SystemFieldNameMappings

DROP TABLE IF EXISTS Sponsors

DROP TABLE IF EXISTS SponsorPersonnel

DROP TABLE IF EXISTS RoleTypes

DROP TABLE IF EXISTS QualityManagementReviews

DROP TABLE IF EXISTS Protocols

DROP TABLE IF EXISTS PhaseCodes

DROP TABLE IF EXISTS Persons

DROP TABLE IF EXISTS PatientSchedules

DROP TABLE IF EXISTS Organizations

DROP TABLE IF EXISTS OrganizationDepartments

DROP TABLE IF EXISTS MilestoneTypes

DROP TABLE IF EXISTS MilestoneSteps

DROP TABLE IF EXISTS Milestones

DROP TABLE IF EXISTS InspectionTypes

DROP TABLE IF EXISTS Inspections

DROP TABLE IF EXISTS InspectionLogs

DROP TABLE IF EXISTS Hospitals

DROP TABLE IF EXISTS HospitalPersonnel

DROP TABLE IF EXISTS EventTypes

DROP TABLE IF EXISTS DocumentTypes

DROP TABLE IF EXISTS Documents

DROP TABLE IF EXISTS DeviationTypes

DROP TABLE IF EXISTS CountryCodes

DROP TABLE IF EXISTS AuthorityTypes

DROP TABLE IF EXISTS AuthoritySteps

DROP TABLE IF EXISTS AuthorityPersonnel

DROP TABLE IF EXISTS Authorities

DROP TABLE IF EXISTS AdverseEvents

DROP TABLE IF EXISTS ActionCodes

/* ============================================ */ /* CREATE TABLES */ /* ============================================ */ /* Table: ActionCodes */
CREATE TABLE ActionCodes (
  ActionCode NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (ActionCode)
)

/* Table: AdverseEvents */
CREATE TABLE AdverseEvents (
  EventID INTEGER NULL,
  TrialID INTEGER NULL,
  EventType NVARCHAR(50) NULL,
  EventDate DATETIME NULL,
  DetectedDate DATETIME NULL,
  ReportDate DATETIME NULL,
  PatientID INTEGER NULL,
  EventDescription NVARCHAR(MAX) NULL,
  Severity NVARCHAR(MAX) NULL,
  Seriousness NVARCHAR(MAX) NULL,
  Causality NVARCHAR(MAX) NULL,
  Outcome NVARCHAR(MAX) NULL,
  ActionTaken NVARCHAR(MAX) NULL,
  ReportedToRegionalEthicsCommittee BIT NULL,
  RegionalEthicsCommitteeReportDate DATETIME NULL,
  ReportedToSLV BIT NULL,
  SLVReportDate DATETIME NULL,
  ReportedToSponsor BIT NULL,
  SponsorReportDate DATETIME NULL,
  FollowUpRequired BIT NULL,
  StatusDescription NVARCHAR(MAX) NULL,
  ClosedDate DATETIME NULL,
  ClosedByTrialPersonnelID INTEGER NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (EventID)
)

/* Table: Authorities */
CREATE TABLE Authorities (
  AuthorityID INTEGER NULL,
  AuthorityType NVARCHAR(50) NULL,
  LegislationCountryCode NVARCHAR(10) NULL,
  OrganizationID INTEGER NULL,
  LongName NVARCHAR(50) NULL,
  AbbriviationName NVARCHAR(50) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (AuthorityID)
)

/* Table: AuthorityPersonnel */
CREATE TABLE AuthorityPersonnel (
  AuthorityPersonnelID INTEGER NULL,
  AuthorityID INTEGER NULL,
  PersonID INTEGER NULL,
  StartDate DATETIME NULL,
  EndDate DATETIME NULL,
  Specialization NVARCHAR(100) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (AuthorityPersonnelID)
)

/* Table: AuthoritySteps */
CREATE TABLE AuthoritySteps (
  AuthorityStepID INTEGER NULL,
  AuthorityID INTEGER NULL,
  OrderIndex INTEGER NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  WindowBeforeDays INTEGER NULL,
  WindowAfterDays INTEGER NULL,
  Required BIT NULL,
  Instructions NVARCHAR(MAX) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (AuthorityStepID)
)

/* Table: AuthorityTypes */
CREATE TABLE AuthorityTypes (
  AuthorityType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (AuthorityType)
)

/* Table: CountryCodes */
CREATE TABLE CountryCodes (
  CountryCode NVARCHAR(10) NULL,
  Name NVARCHAR(50) NULL,
  PhoneCountryCode NVARCHAR(10) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (CountryCode)
)

/* Table: DeviationTypes */
CREATE TABLE DeviationTypes (
  DeviationType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(255) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (DeviationType)
)

/* Table: Documents */
CREATE TABLE Documents (
  DocumentID INTEGER NULL,
  TrialID INTEGER NULL,
  DocumentType NVARCHAR(50) NULL,
  DocumentName NVARCHAR(255) NULL,
  Description NVARCHAR(255) NULL,
  Version NVARCHAR(20) NULL,
  DocumentDate DATETIME NULL,
  ApprovedDate DATETIME NULL,
  ApprovedBySponsorPersonnelID INTEGER NULL,
  ApprovedByHospitalPersonnelID INTEGER NULL,
  DocumentLocation NVARCHAR(255) NULL,
  FilePath NVARCHAR(255) NULL,
  FileFormat NVARCHAR(20) NULL,
  Status NVARCHAR(50) NULL,
  IsCurrent BIT NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (DocumentID)
)

/* Table: DocumentTypes */
CREATE TABLE DocumentTypes (
  DocumentType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (DocumentType)
)

/* Table: EventTypes */
CREATE TABLE EventTypes (
  EventType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(255) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (EventType)
)

/* Table: HospitalPersonnel */
CREATE TABLE HospitalPersonnel (
  HospitalPersonnelID INTEGER NULL,
  HospitalID INTEGER NULL,
  PersonID INTEGER NULL,
  StartDate DATETIME NULL,
  EndDate DATETIME NULL,
  Specialization NVARCHAR(100) NULL,
  Notes NVARCHAR(MAX) NULL,
  UserAccessType NVARCHAR(255) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (HospitalPersonnelID)
)

/* Table: Hospitals */
CREATE TABLE Hospitals (
  HospitalID INTEGER NULL,
  OrganizationID INTEGER NULL,
  LegislativeCountryCode NVARCHAR(10) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (HospitalID)
)

/* Table: InspectionLogs */
CREATE TABLE InspectionLogs (
  InspectionLogID INTEGER NULL,
  InspectionID INTEGER NULL,
  Findings NVARCHAR(MAX) NULL,
  IsCritical BIT NULL,
  IsFollowUpRequired BIT NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (InspectionLogID)
)

/* Table: Inspections */
CREATE TABLE Inspections (
  InspectionID INTEGER NULL,
  TrialID INTEGER NULL,
  InspectionType NVARCHAR(50) NULL,
  InspectionDate DATETIME NULL,
  SponsorTrialRoleID INTEGER NULL,
  TrialPersonnelID INTEGER NULL,
  EstimatedStartDateTime DATETIME NULL,
  EstimatedEndDateTime DATETIME NULL,
  ActualStartDateTime DATETIME NULL,
  ActualEndDateTime DATETIME NULL,
  PlannedDuration FLOAT NULL,
  ActualDuration FLOAT NULL,
  FindingsCount INTEGER NULL,
  MajorFindings INTEGER NULL,
  MinorFindings INTEGER NULL,
  CriticalFindings INTEGER NULL,
  FollowUpRequired BIT NULL,
  FollowUpDate DATETIME NULL,
  FollowUpCompleted BIT NULL,
  ReportReceived BIT NULL,
  ReportDate DATETIME NULL,
  ReportLocation NVARCHAR(255) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (InspectionID)
)

/* Table: InspectionTypes */
CREATE TABLE InspectionTypes (
  InspectionType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(255) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (InspectionType)
)

/* Table: Milestones */
CREATE TABLE Milestones (
  MilestoneID INTEGER NULL,
  TrialID INTEGER NULL,
  MilestoneName NVARCHAR(50) NULL,
  MilestoneType NVARCHAR(50) NULL,
  PlannedDate DATETIME NULL,
  ActualDate DATETIME NULL,
  Status NVARCHAR(50) NULL,
  InvolvesAuthorityID INTEGER NULL,
  ResponsibleTrialRoleID INTEGER NULL,
  Critical BIT NULL,
  Completed BIT NULL,
  TransitionPhaseCode NVARCHAR(20) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (MilestoneID)
)

/* Table: MilestoneSteps */
CREATE TABLE MilestoneSteps (
  MilestoneStepID INTEGER NULL,
  MilestoneID INTEGER NULL,
  ActionCode NVARCHAR(50) NULL,
  AuthorityStepID INTEGER NULL,
  TrialRoleID INTEGER NULL,
  ReferenceNumber NVARCHAR(100) NULL,
  SubmittedDate DATETIME NULL,
  ApprovedDate DATETIME NULL,
  ExpiryDate DATETIME NULL,
  DocumentationLocation NVARCHAR(255) NULL,
  Status NVARCHAR(50) NULL,
  Version NVARCHAR(20) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (MilestoneStepID)
)

/* Table: MilestoneTypes */
CREATE TABLE MilestoneTypes (
  MilestoneType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (MilestoneType)
)

/* Table: OrganizationDepartments */
CREATE TABLE OrganizationDepartments (
  OrganizationDepartmentID INTEGER NULL,
  OrganizationID INTEGER NULL,
  DepartmentName NVARCHAR(50) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (OrganizationDepartmentID)
)

/* Table: Organizations */
CREATE TABLE Organizations (
  OrganizationID INTEGER NULL,
  OrganizationNumber NVARCHAR(20) NULL,
  OrganizationName NVARCHAR(50) NULL,
  CountryCode NVARCHAR(10) NULL,
  Address NVARCHAR(100) NULL,
  PostalCode NVARCHAR(20) NULL,
  City NVARCHAR(50) NULL,
  Phone NVARCHAR(50) NULL,
  Email NVARCHAR(50) NULL,
  Website NVARCHAR(255) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (OrganizationID)
)

/* Table: PatientSchedules */
CREATE TABLE PatientSchedules (
  PatientScheduleID INTEGER NULL,
  TrialID INTEGER NULL,
  Description NVARCHAR(MAX) NULL,
  Name NVARCHAR(50) NULL,
  OffsetDays INTEGER NULL,
  WindowBeforeDays INTEGER NULL,
  WindowAfterDays INTEGER NULL,
  AffectedByProtocolID INTEGER NULL,
  Required BIT NULL,
  Instructions NVARCHAR(MAX) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (PatientScheduleID)
)

/* Table: Persons */
CREATE TABLE Persons (
  PersonID INTEGER NULL,
  FirstName NVARCHAR(50) NULL,
  LastName NVARCHAR(50) NULL,
  Title NVARCHAR(50) NULL,
  CountryCode NVARCHAR(10) NULL,
  Phone NVARCHAR(50) NULL,
  Mobile NVARCHAR(50) NULL,
  Email NVARCHAR(50) NULL,
  Gender NVARCHAR(20) NULL,
  BirthDate NVARCHAR(50) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (PersonID)
)

/* Table: PhaseCodes */
CREATE TABLE PhaseCodes (
  PhaseCode NVARCHAR(20) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (PhaseCode)
)

/* Table: Protocols */
CREATE TABLE Protocols (
  ProtocolID INTEGER NULL,
  TrialID INTEGER NULL,
  ProtocolReference NVARCHAR(100) NULL,
  EffectiveDate DATETIME NULL,
  ValidFromDate DATETIME NULL,
  ValidToDate DATETIME NULL,
  ProtocolDescription NVARCHAR(MAX) NULL,
  DocumentID INTEGER NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (ProtocolID)
)

/* Table: QualityManagementReviews */
CREATE TABLE QualityManagementReviews (
  QualityManagementReviewID INTEGER NULL,
  TrialID INTEGER NULL,
  ActivityType NVARCHAR(50) NULL,
  ActivityDate DATETIME NULL,
  PerformedByTrialPersonnelID INTEGER NULL,
  Scope NVARCHAR(MAX) NULL,
  Findings NVARCHAR(MAX) NULL,
  Recommendations NVARCHAR(MAX) NULL,
  ActionsRequired NVARCHAR(MAX) NULL,
  ActionDueDate DATETIME NULL,
  ActionCompletedDate DATETIME NULL,
  ReportLocationDescription NVARCHAR(50) NULL,
  ReportDocumentID INTEGER NULL,
  IsResolved BIT NULL,
  ResolvedByTrialPersonnelID INTEGER NULL,
  ResolvedDate DATETIME NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (QualityManagementReviewID)
)

/* Table: RoleTypes */
CREATE TABLE RoleTypes (
  RoleType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (RoleType)
)

/* Table: SponsorPersonnel */
CREATE TABLE SponsorPersonnel (
  SponsorPersonnelID INTEGER NULL,
  SponsorID INTEGER NULL,
  PersonID INTEGER NULL,
  StartDate DATETIME NULL,
  EndDate DATETIME NULL,
  Specialization NVARCHAR(100) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (SponsorPersonnelID)
)

/* Table: Sponsors */
CREATE TABLE Sponsors (
  SponsorID INTEGER NULL,
  OrganizationID INTEGER NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (SponsorID)
)

/* Table: SystemFieldNameMappings */
CREATE TABLE SystemFieldNameMappings (
  Name NVARCHAR(50) NOT NULL,
  TranslationValue NVARCHAR(50) NULL,
  LanguageCode NVARCHAR(50) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (Name)
)

/* Table: SystemLogs */
CREATE TABLE SystemLogs (
  UserName NVARCHAR(50) NOT NULL,
  FormName NVARCHAR(50) NULL,
  ControlName NVARCHAR(255) NULL,
  Severity NVARCHAR(255) NULL,
  LogMessage NVARCHAR(255) NULL,
  LogData NVARCHAR(MAX) NULL,
  LogDateTime DATETIME NULL DEFAULT NOW()
)

/* Table: SystemTableNameMappings */
CREATE TABLE SystemTableNameMappings (
  Name NVARCHAR(50) NOT NULL,
  TranslationValue NVARCHAR(50) NULL,
  LanguageCode NVARCHAR(50) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (Name)
)

/* Table: TrialDeviations */
CREATE TABLE TrialDeviations (
  DeviationID INTEGER NULL,
  TrialID INTEGER NULL,
  DeviationDate DATETIME NULL,
  DetectedDate DATETIME NULL,
  DeviationType NVARCHAR(50) NULL,
  Severity NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  ImmediateAction NVARCHAR(MAX) NULL,
  RootCause NVARCHAR(MAX) NULL,
  CAPA NVARCHAR(MAX) NULL,
  CAPADueDate DATETIME NULL,
  CAPACompletedDate DATETIME NULL,
  ReportedToRegionalEthicsCommittee BIT NULL,
  RegionalEthicsCommitteeReportDate DATETIME NULL,
  ReportedToSponsor BIT NULL,
  SponsorReportDate DATETIME NULL,
  ResponsibleTrialRoleID INTEGER NULL,
  Status NVARCHAR(50) NULL,
  ClosedDate DATETIME NULL,
  ClosedByTrialPersonnelID INTEGER NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (DeviationID)
)

/* Table: TrialPatients */
CREATE TABLE TrialPatients (
  PatientID INTEGER NULL,
  TrialID INTEGER NULL,
  PatientCode NVARCHAR(50) NULL,
  ScreeningDate DATETIME NULL,
  EnrollmentDate DATETIME NULL,
  ApprovalDate DATETIME NULL,
  CompletionDate DATETIME NULL,
  WithdrawalDate DATETIME NULL,
  PatientStatus NVARCHAR(50) NULL,
  DisqualificationReason NVARCHAR(MAX) NULL,
  AgeAtScreening INTEGER NULL,
  Gender NVARCHAR(20) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (PatientID)
)

/* Table: TrialPersonnel */
CREATE TABLE TrialPersonnel (
  TrialPersonnelID INTEGER NULL,
  TrialID INTEGER NULL,
  TrialPersonnelType NVARCHAR(50) NULL,
  HospitalPersonnelID INTEGER NULL,
  SponsorPersonnelID INTEGER NULL,
  AuthorityPersonnelID INTEGER NULL,
  IsPrimary BIT NULL,
  StartDate DATETIME NULL,
  EndDate DATETIME NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (TrialPersonnelID)
)

/* Table: TrialPersonnelTypes */
CREATE TABLE TrialPersonnelTypes (
  TrialPersonnelType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (TrialPersonnelType)
)

/* Table: TrialRoles */
CREATE TABLE TrialRoles (
  TrialRoleID INTEGER NULL,
  TrialID INTEGER NULL,
  TrialPersonnelID INTEGER NULL,
  RoleType NVARCHAR(50) NULL,
  IsPrimary BIT NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (TrialRoleID)
)

/* Table: Trials */
CREATE TABLE Trials (
  TrialID INTEGER NULL,
  HospitalID INTEGER NULL,
  SponsorID INTEGER NULL,
  TrialType NVARCHAR(50) NULL,
  TrialTitle NVARCHAR(50) NULL,
  Indication NVARCHAR(MAX) NULL,
  EudraCTNumber NVARCHAR(50) NULL,
  ClinicalTrialsGovID NVARCHAR(50) NULL,
  PlannedEnrollment INTEGER NULL,
  ActualEnrollment INTEGER NULL,
  NumberScreened INTEGER NULL,
  NumberIncluded INTEGER NULL,
  PlannedStartDate DATETIME NULL,
  FirstPatientInDate DATETIME NULL,
  LastPatientOutDate DATETIME NULL,
  DatabaseLockDate DATETIME NULL,
  ReportSentDate DATETIME NULL,
  ArchivingDate DATETIME NULL,
  OverallStatus NVARCHAR(50) NULL,
  ProtocolVersion NVARCHAR(20) NULL,
  CurrentProtocolID INTEGER NULL,
  CurrentPhaseCode NVARCHAR(20) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (TrialID)
)

/* Table: TrialTypes */
CREATE TABLE TrialTypes (
  TrialType NVARCHAR(50) NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(MAX) NULL,
  Instructions NVARCHAR(MAX) NULL,
  Notes NVARCHAR(MAX) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (TrialType)
)

/* Table: UserAccessTypes */
CREATE TABLE UserAccessTypes (
  UserAccessType NVARCHAR(50) NOT NULL,
  Name NVARCHAR(50) NULL,
  Description NVARCHAR(255) NULL,
  CreatedDate DATETIME NULL,
  ModifiedDate DATETIME NULL,
  CreatedBy NVARCHAR(20) NULL,
  ModifiedBy NVARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT (1 = 0),
  PRIMARY KEY (UserAccessType)
)

/* ============================================ */ /* CREATE INDEXES */ /* ============================================ */
CREATE INDEX FK_AdverseEvents_ClosedByTrialPersonnel ON AdverseEvents(ClosedByTrialPersonnelID)

CREATE INDEX FK_AdverseEvents_EventType ON AdverseEvents(EventType)

CREATE INDEX FK_AdverseEvents_Trial ON AdverseEvents(TrialID)

CREATE INDEX FK_AdverseEvents_TrialPatient ON AdverseEvents(PatientID)

CREATE INDEX idx_AdverseEvents_EventDate ON AdverseEvents(EventDate)

CREATE INDEX idx_AdverseEvents_EventType ON AdverseEvents(EventType)

CREATE INDEX idx_AdverseEvents_TrialID ON AdverseEvents(TrialID)

CREATE INDEX FK_Authorities_AuthorityTypes ON Authorities(AuthorityType)

CREATE INDEX FK_Authorities_LegislationCountry ON Authorities(LegislationCountryCode)

CREATE INDEX FK_Authorities_Organizations ON Authorities(OrganizationID)

CREATE INDEX FK_AuthorityPersonnel_Authority ON AuthorityPersonnel(AuthorityID)

CREATE INDEX FK_AuthorityPersonnel_Person ON AuthorityPersonnel(PersonID)

CREATE INDEX FK_AuthoritySteps_Authority ON AuthoritySteps(AuthorityID)

CREATE INDEX FK_Documents_ApprovedByHospitalPersonnel ON Documents(ApprovedByHospitalPersonnelID)

CREATE INDEX FK_Documents_ApprovedBySponsorPersonnel ON Documents(ApprovedBySponsorPersonnelID)

CREATE INDEX FK_Documents_DocumentType ON Documents(DocumentType)

CREATE INDEX FK_Documents_Trial ON Documents(TrialID)

CREATE INDEX idx_Documents_DocumentType ON Documents(DocumentType)

CREATE INDEX idx_Documents_Status ON Documents(Status)

CREATE INDEX idx_Documents_TrialID ON Documents(TrialID)

CREATE INDEX FK_HospitalPersonnel_Hospitals ON HospitalPersonnel(HospitalID)

CREATE INDEX FK_HospitalPersonnel_Person ON HospitalPersonnel(PersonID)

CREATE INDEX FK_Hospital_CountryCodes ON Hospitals(LegislativeCountryCode)

CREATE INDEX FK_Hospital_Organizations ON Hospitals(OrganizationID)

CREATE INDEX FK_InspectionLogs_Inspection ON InspectionLogs(InspectionID)

CREATE INDEX FK_Inspections_InspectionTypes ON Inspections(InspectionType)

CREATE INDEX FK_Inspections_SponsorTrialRole ON Inspections(SponsorTrialRoleID)

CREATE INDEX FK_Inspections_Trial ON Inspections(TrialID)

CREATE INDEX FK_Inspections_TrialPersonnel ON Inspections(TrialPersonnelID)

CREATE INDEX idx_Inspections_InspectionDate ON Inspections(InspectionDate)

CREATE INDEX idx_Inspections_InspectionType ON Inspections(InspectionType)

CREATE INDEX idx_Inspections_TrialID ON Inspections(TrialID)

CREATE INDEX FK_Milestones_Authority ON Milestones(InvolvesAuthorityID)

CREATE INDEX FK_Milestones_MilestoneTypes ON Milestones(MilestoneType)

CREATE INDEX FK_Milestones_ResponsibleTrialRole ON Milestones(ResponsibleTrialRoleID)

CREATE INDEX FK_Milestones_TransitionPhaseCodes ON Milestones(TransitionPhaseCode)

CREATE INDEX FK_Milestones_Trial ON Milestones(TrialID)

CREATE INDEX idx_Milestones_MilestoneType ON Milestones(MilestoneType)

CREATE INDEX idx_Milestones_PlannedDate ON Milestones(PlannedDate)

CREATE INDEX idx_Milestones_Status ON Milestones(Status)

CREATE INDEX idx_Milestones_TrialID ON Milestones(TrialID)

CREATE INDEX FK_MilestoneSteps_ActionCodes ON MilestoneSteps(ActionCode)

CREATE INDEX FK_MilestoneSteps_AuthorityStep ON MilestoneSteps(AuthorityStepID)

CREATE INDEX FK_MilestoneSteps_Milestone ON MilestoneSteps(MilestoneID)

CREATE INDEX FK_MilestoneSteps_TrialRole ON MilestoneSteps(TrialRoleID)

CREATE INDEX FK_OrganizationDepartment_Organizations ON OrganizationDepartments(OrganizationID)

CREATE INDEX FK_Organization_CountryCodes ON Organizations(CountryCode)

CREATE INDEX idx_Organization_CountryCodes ON Organizations(CountryCode)

CREATE INDEX FK_PatientSchedules_Protocol ON PatientSchedules(AffectedByProtocolID)

CREATE INDEX FK_PatientSchedules_Trial ON PatientSchedules(TrialID)

CREATE INDEX FK_Persons_CountryCodes ON Persons(CountryCode)

CREATE INDEX FK_Protocols_Document ON Protocols(DocumentID)

CREATE INDEX FK_Protocols_Trial ON Protocols(TrialID)

CREATE INDEX FK_QualityManagementLogs_ReportDocument ON QualityManagementReviews(ReportDocumentID)

CREATE INDEX FK_QualityManagementLogs_ResolvedByTrialPersonnel ON QualityManagementReviews(ResolvedByTrialPersonnelID)

CREATE INDEX FK_QualityManagementLogs_Trial ON QualityManagementReviews(TrialID)

CREATE INDEX FK_QualityManagementLogs_TrialPersonnel ON QualityManagementReviews(PerformedByTrialPersonnelID)

CREATE INDEX idx_QualityManagementLogs_ActivityType ON QualityManagementReviews(ActivityType)

CREATE INDEX idx_QualityManagementLogs_TrialID ON QualityManagementReviews(TrialID)

CREATE INDEX FK_SponsorPersonnel_Person ON SponsorPersonnel(PersonID)

CREATE INDEX FK_SponsorPersonnel_Sponsor ON SponsorPersonnel(SponsorID)

CREATE INDEX FK_Sponsors_Organizations ON Sponsors(OrganizationID)

CREATE INDEX FK_TrialDeviations_DeviationTypes ON TrialDeviations(DeviationType)

CREATE INDEX FK_TrialDeviations_ResponsibleTrialRole ON TrialDeviations(ResponsibleTrialRoleID)

CREATE INDEX FK_TrialDeviations_Trial ON TrialDeviations(TrialID)

CREATE INDEX idx_TrialDeviations_DeviationDate ON TrialDeviations(DeviationDate)

CREATE INDEX idx_TrialDeviations_Status ON TrialDeviations(Status)

CREATE INDEX idx_TrialDeviations_TrialID ON TrialDeviations(TrialID)

CREATE INDEX FK_TrialPatients_Trial ON TrialPatients(TrialID)

CREATE INDEX idx_TrialPatients_PatientStatus ON TrialPatients(PatientStatus)

CREATE INDEX idx_TrialPatients_TrialID ON TrialPatients(TrialID)

CREATE INDEX FK_TrialPersonnel_AuthorityPersonnel ON TrialPersonnel(AuthorityPersonnelID)

CREATE INDEX FK_TrialPersonnel_HospitalPersonnel ON TrialPersonnel(HospitalPersonnelID)

CREATE INDEX FK_TrialPersonnel_SponsorPersonnel ON TrialPersonnel(SponsorPersonnelID)

CREATE INDEX FK_TrialPersonnel_Trial ON TrialPersonnel(TrialID)

CREATE INDEX FK_TrialPersonnel_TrialPersonnelType ON TrialPersonnel(TrialPersonnelType)

CREATE INDEX idx_TrialPersonnel_TrialID ON TrialPersonnel(TrialID)

CREATE INDEX idx_TrialPersonnel_TrialPersonnelType ON TrialPersonnel(TrialPersonnelType)

CREATE INDEX FK_TrialRoles_RoleType ON TrialRoles(RoleType)

CREATE INDEX FK_TrialRoles_Trial ON TrialRoles(TrialID)

CREATE INDEX FK_TrialRoles_TrialPersonnel ON TrialRoles(TrialPersonnelID)

CREATE INDEX idx_TrialRoles_RoleType ON TrialRoles(RoleType)

CREATE INDEX idx_TrialRoles_TrialID ON TrialRoles(TrialID)

CREATE INDEX idx_TrialRoles_TrialPersonnelID ON TrialRoles(TrialPersonnelID)

CREATE INDEX FK_Trials_CurrentPhaseCodes ON Trials(CurrentPhaseCode)

CREATE INDEX FK_Trials_CurrentProtocol ON Trials(CurrentProtocolID)

CREATE INDEX FK_Trials_Hospitals ON Trials(HospitalID)

CREATE INDEX FK_Trials_Sponsor ON Trials(SponsorID)

CREATE INDEX FK_Trials_TrialTypes ON Trials(TrialType)

CREATE INDEX idx_Trials_CurrentPhaseCodes ON Trials(CurrentPhaseCode)

CREATE INDEX idx_Trials_HospitalID ON Trials(HospitalID)

CREATE INDEX idx_Trials_OverallStatus ON Trials(OverallStatus)

CREATE INDEX idx_Trials_PlannedStartDate ON Trials(PlannedStartDate)

CREATE INDEX idx_Trials_SponsorID ON Trials(SponsorID)

CREATE INDEX idx_Trials_TrialType ON Trials(TrialType)

ALTER TABLE AdverseEvents
  ADD CONSTRAINT FK_AdverseEvents_ClosedByTrialPersonnel FOREIGN KEY (ClosedByTrialPersonnelID) REFERENCES TrialPersonnel (
    TrialPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION
 /* ============================================ */ /* FOREIGN KEY CONSTRAINTS */ /* ============================================ */

ALTER TABLE AdverseEvents
  ADD CONSTRAINT FK_AdverseEvents_EventType FOREIGN KEY (EventType) REFERENCES EventTypes (
    EventType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE AdverseEvents
  ADD CONSTRAINT FK_AdverseEvents_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE AdverseEvents
  ADD CONSTRAINT FK_AdverseEvents_TrialPatient FOREIGN KEY (PatientID) REFERENCES TrialPatients (
    PatientID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Authorities
  ADD CONSTRAINT FK_Authorities_AuthorityTypes FOREIGN KEY (AuthorityType) REFERENCES AuthorityTypes (
    AuthorityType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Authorities
  ADD CONSTRAINT FK_Authorities_LegislationCountry FOREIGN KEY (LegislationCountryCode) REFERENCES CountryCodes (
    CountryCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Authorities
  ADD CONSTRAINT FK_Authorities_Organizations FOREIGN KEY (OrganizationID) REFERENCES Organizations (
    OrganizationID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE AuthorityPersonnel
  ADD CONSTRAINT FK_AuthorityPersonnel_Authority FOREIGN KEY (AuthorityID) REFERENCES Authorities (
    AuthorityID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE AuthorityPersonnel
  ADD CONSTRAINT FK_AuthorityPersonnel_Person FOREIGN KEY (PersonID) REFERENCES Persons (
    PersonID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE AuthoritySteps
  ADD CONSTRAINT FK_AuthoritySteps_Authority FOREIGN KEY (AuthorityID) REFERENCES Authorities (
    AuthorityID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Documents
  ADD CONSTRAINT FK_Documents_ApprovedByHospitalPersonnel FOREIGN KEY (ApprovedByHospitalPersonnelID) REFERENCES HospitalPersonnel (
    HospitalPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Documents
  ADD CONSTRAINT FK_Documents_ApprovedBySponsorPersonnel FOREIGN KEY (ApprovedBySponsorPersonnelID) REFERENCES SponsorPersonnel (
    SponsorPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Documents
  ADD CONSTRAINT FK_Documents_DocumentType FOREIGN KEY (DocumentType) REFERENCES DocumentTypes (
    DocumentType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Documents
  ADD CONSTRAINT FK_Documents_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Hospitals
  ADD CONSTRAINT FK_Hospital_CountryCodes FOREIGN KEY (LegislativeCountryCode) REFERENCES CountryCodes (
    CountryCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Hospitals
  ADD CONSTRAINT FK_Hospital_Organizations FOREIGN KEY (OrganizationID) REFERENCES Organizations (
    OrganizationID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE HospitalPersonnel
  ADD CONSTRAINT FK_HospitalPersonnel_Hospitals FOREIGN KEY (HospitalID) REFERENCES Hospitals (
    HospitalID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE HospitalPersonnel
  ADD CONSTRAINT FK_HospitalPersonnel_Person FOREIGN KEY (PersonID) REFERENCES Persons (
    PersonID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE InspectionLogs
  ADD CONSTRAINT FK_InspectionLogs_Inspection FOREIGN KEY (InspectionID) REFERENCES Inspections (
    InspectionID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Inspections
  ADD CONSTRAINT FK_Inspections_InspectionTypes FOREIGN KEY (InspectionType) REFERENCES InspectionTypes (
    InspectionType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Inspections
  ADD CONSTRAINT FK_Inspections_SponsorTrialRole FOREIGN KEY (SponsorTrialRoleID) REFERENCES TrialRoles (
    TrialRoleID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Inspections
  ADD CONSTRAINT FK_Inspections_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Inspections
  ADD CONSTRAINT FK_Inspections_TrialPersonnel FOREIGN KEY (TrialPersonnelID) REFERENCES TrialPersonnel (
    TrialPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Milestones
  ADD CONSTRAINT FK_Milestones_Authority FOREIGN KEY (InvolvesAuthorityID) REFERENCES Authorities (
    AuthorityID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Milestones
  ADD CONSTRAINT FK_Milestones_MilestoneTypes FOREIGN KEY (MilestoneType) REFERENCES MilestoneTypes (
    MilestoneType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Milestones
  ADD CONSTRAINT FK_Milestones_ResponsibleTrialRole FOREIGN KEY (ResponsibleTrialRoleID) REFERENCES TrialRoles (
    TrialRoleID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Milestones
  ADD CONSTRAINT FK_Milestones_TransitionPhaseCodes FOREIGN KEY (TransitionPhaseCode) REFERENCES PhaseCodes (
    PhaseCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Milestones
  ADD CONSTRAINT FK_Milestones_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE MilestoneSteps
  ADD CONSTRAINT FK_MilestoneSteps_ActionCodes FOREIGN KEY (ActionCode) REFERENCES ActionCodes (
    ActionCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE MilestoneSteps
  ADD CONSTRAINT FK_MilestoneSteps_AuthorityStep FOREIGN KEY (AuthorityStepID) REFERENCES AuthoritySteps (
    AuthorityStepID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE MilestoneSteps
  ADD CONSTRAINT FK_MilestoneSteps_Milestone FOREIGN KEY (MilestoneID) REFERENCES Milestones (
    MilestoneID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE MilestoneSteps
  ADD CONSTRAINT FK_MilestoneSteps_TrialRole FOREIGN KEY (TrialRoleID) REFERENCES TrialRoles (
    TrialRoleID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Organizations
  ADD CONSTRAINT FK_Organization_CountryCodes FOREIGN KEY (CountryCode) REFERENCES CountryCodes (
    CountryCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE OrganizationDepartments
  ADD CONSTRAINT FK_OrganizationDepartment_Organizations FOREIGN KEY (OrganizationID) REFERENCES Organizations (
    OrganizationID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE PatientSchedules
  ADD CONSTRAINT FK_PatientSchedules_Protocol FOREIGN KEY (AffectedByProtocolID) REFERENCES Protocols (
    ProtocolID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE PatientSchedules
  ADD CONSTRAINT FK_PatientSchedules_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Persons
  ADD CONSTRAINT FK_Persons_CountryCodes FOREIGN KEY (CountryCode) REFERENCES CountryCodes (
    CountryCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Protocols
  ADD CONSTRAINT FK_Protocols_Document FOREIGN KEY (DocumentID) REFERENCES Documents (
    DocumentID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Protocols
  ADD CONSTRAINT FK_Protocols_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE QualityManagementReviews
  ADD CONSTRAINT FK_QualityManagementLogs_ReportDocument FOREIGN KEY (ReportDocumentID) REFERENCES Documents (
    DocumentID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE QualityManagementReviews
  ADD CONSTRAINT FK_QualityManagementLogs_ResolvedByTrialPersonnel FOREIGN KEY (ResolvedByTrialPersonnelID) REFERENCES TrialPersonnel (
    TrialPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE QualityManagementReviews
  ADD CONSTRAINT FK_QualityManagementLogs_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE QualityManagementReviews
  ADD CONSTRAINT FK_QualityManagementLogs_TrialPersonnel FOREIGN KEY (PerformedByTrialPersonnelID) REFERENCES TrialPersonnel (
    TrialPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE SponsorPersonnel
  ADD CONSTRAINT FK_SponsorPersonnel_Person FOREIGN KEY (PersonID) REFERENCES Persons (
    PersonID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE SponsorPersonnel
  ADD CONSTRAINT FK_SponsorPersonnel_Sponsor FOREIGN KEY (SponsorID) REFERENCES Sponsors (
    SponsorID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Sponsors
  ADD CONSTRAINT FK_Sponsors_Organizations FOREIGN KEY (OrganizationID) REFERENCES Organizations (
    OrganizationID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialDeviations
  ADD CONSTRAINT FK_TrialDeviations_DeviationTypes FOREIGN KEY (DeviationType) REFERENCES DeviationTypes (
    DeviationType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialDeviations
  ADD CONSTRAINT FK_TrialDeviations_ResponsibleTrialRole FOREIGN KEY (ResponsibleTrialRoleID) REFERENCES TrialRoles (
    TrialRoleID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialDeviations
  ADD CONSTRAINT FK_TrialDeviations_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialPatients
  ADD CONSTRAINT FK_TrialPatients_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialPersonnel
  ADD CONSTRAINT FK_TrialPersonnel_AuthorityPersonnel FOREIGN KEY (AuthorityPersonnelID) REFERENCES AuthorityPersonnel (
    AuthorityPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialPersonnel
  ADD CONSTRAINT FK_TrialPersonnel_HospitalPersonnel FOREIGN KEY (HospitalPersonnelID) REFERENCES HospitalPersonnel (
    HospitalPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialPersonnel
  ADD CONSTRAINT FK_TrialPersonnel_SponsorPersonnel FOREIGN KEY (SponsorPersonnelID) REFERENCES SponsorPersonnel (
    SponsorPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialPersonnel
  ADD CONSTRAINT FK_TrialPersonnel_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialPersonnel
  ADD CONSTRAINT FK_TrialPersonnel_TrialPersonnelType FOREIGN KEY (TrialPersonnelType) REFERENCES TrialPersonnelTypes (
    TrialPersonnelType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialRoles
  ADD CONSTRAINT FK_TrialRoles_RoleType FOREIGN KEY (RoleType) REFERENCES RoleTypes (
    RoleType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialRoles
  ADD CONSTRAINT FK_TrialRoles_Trial FOREIGN KEY (TrialID) REFERENCES Trials (
    TrialID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE TrialRoles
  ADD CONSTRAINT FK_TrialRoles_TrialPersonnel FOREIGN KEY (TrialPersonnelID) REFERENCES TrialPersonnel (
    TrialPersonnelID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Trials
  ADD CONSTRAINT FK_Trials_CurrentPhaseCodes FOREIGN KEY (CurrentPhaseCode) REFERENCES PhaseCodes (
    PhaseCode
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Trials
  ADD CONSTRAINT FK_Trials_CurrentProtocol FOREIGN KEY (CurrentProtocolID) REFERENCES Protocols (
    ProtocolID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Trials
  ADD CONSTRAINT FK_Trials_Hospitals FOREIGN KEY (HospitalID) REFERENCES Hospitals (
    HospitalID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Trials
  ADD CONSTRAINT FK_Trials_Sponsor FOREIGN KEY (SponsorID) REFERENCES Sponsors (
    SponsorID
  ) ON UPDATE NO ACTION ON DELETE NO ACTION

ALTER TABLE Trials
  ADD CONSTRAINT FK_Trials_TrialTypes FOREIGN KEY (TrialType) REFERENCES TrialTypes (
    TrialType
  ) ON UPDATE NO ACTION ON DELETE NO ACTION