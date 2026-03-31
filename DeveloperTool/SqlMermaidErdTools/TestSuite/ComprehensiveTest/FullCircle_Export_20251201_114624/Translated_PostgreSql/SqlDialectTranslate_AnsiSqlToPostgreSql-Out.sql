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
  ActionCode VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (ActionCode NULLS FIRST)
)

/* Table: AdverseEvents */
CREATE TABLE AdverseEvents (
  EventID INT NULL,
  TrialID INT NULL,
  EventType VARCHAR(50) NULL,
  EventDate TIMESTAMP NULL,
  DetectedDate TIMESTAMP NULL,
  ReportDate TIMESTAMP NULL,
  PatientID INT NULL,
  EventDescription VARCHAR(MAX) NULL,
  Severity VARCHAR(MAX) NULL,
  Seriousness VARCHAR(MAX) NULL,
  Causality VARCHAR(MAX) NULL,
  Outcome VARCHAR(MAX) NULL,
  ActionTaken VARCHAR(MAX) NULL,
  ReportedToRegionalEthicsCommittee BIT NULL,
  RegionalEthicsCommitteeReportDate TIMESTAMP NULL,
  ReportedToSLV BIT NULL,
  SLVReportDate TIMESTAMP NULL,
  ReportedToSponsor BIT NULL,
  SponsorReportDate TIMESTAMP NULL,
  FollowUpRequired BIT NULL,
  StatusDescription VARCHAR(MAX) NULL,
  ClosedDate TIMESTAMP NULL,
  ClosedByTrialPersonnelID INT NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (EventID NULLS FIRST)
)

/* Table: Authorities */
CREATE TABLE Authorities (
  AuthorityID INT NULL,
  AuthorityType VARCHAR(50) NULL,
  LegislationCountryCode VARCHAR(10) NULL,
  OrganizationID INT NULL,
  LongName VARCHAR(50) NULL,
  AbbriviationName VARCHAR(50) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (AuthorityID NULLS FIRST)
)

/* Table: AuthorityPersonnel */
CREATE TABLE AuthorityPersonnel (
  AuthorityPersonnelID INT NULL,
  AuthorityID INT NULL,
  PersonID INT NULL,
  StartDate TIMESTAMP NULL,
  EndDate TIMESTAMP NULL,
  Specialization VARCHAR(100) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (AuthorityPersonnelID NULLS FIRST)
)

/* Table: AuthoritySteps */
CREATE TABLE AuthoritySteps (
  AuthorityStepID INT NULL,
  AuthorityID INT NULL,
  OrderIndex INT NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  WindowBeforeDays INT NULL,
  WindowAfterDays INT NULL,
  Required BIT NULL,
  Instructions VARCHAR(MAX) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (AuthorityStepID NULLS FIRST)
)

/* Table: AuthorityTypes */
CREATE TABLE AuthorityTypes (
  AuthorityType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (AuthorityType NULLS FIRST)
)

/* Table: CountryCodes */
CREATE TABLE CountryCodes (
  CountryCode VARCHAR(10) NULL,
  Name VARCHAR(50) NULL,
  PhoneCountryCode VARCHAR(10) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (CountryCode NULLS FIRST)
)

/* Table: DeviationTypes */
CREATE TABLE DeviationTypes (
  DeviationType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(255) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (DeviationType NULLS FIRST)
)

/* Table: Documents */
CREATE TABLE Documents (
  DocumentID INT NULL,
  TrialID INT NULL,
  DocumentType VARCHAR(50) NULL,
  DocumentName VARCHAR(255) NULL,
  Description VARCHAR(255) NULL,
  Version VARCHAR(20) NULL,
  DocumentDate TIMESTAMP NULL,
  ApprovedDate TIMESTAMP NULL,
  ApprovedBySponsorPersonnelID INT NULL,
  ApprovedByHospitalPersonnelID INT NULL,
  DocumentLocation VARCHAR(255) NULL,
  FilePath VARCHAR(255) NULL,
  FileFormat VARCHAR(20) NULL,
  Status VARCHAR(50) NULL,
  IsCurrent BIT NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (DocumentID NULLS FIRST)
)

/* Table: DocumentTypes */
CREATE TABLE DocumentTypes (
  DocumentType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (DocumentType NULLS FIRST)
)

/* Table: EventTypes */
CREATE TABLE EventTypes (
  EventType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(255) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (EventType NULLS FIRST)
)

/* Table: HospitalPersonnel */
CREATE TABLE HospitalPersonnel (
  HospitalPersonnelID INT NULL,
  HospitalID INT NULL,
  PersonID INT NULL,
  StartDate TIMESTAMP NULL,
  EndDate TIMESTAMP NULL,
  Specialization VARCHAR(100) NULL,
  Notes VARCHAR(MAX) NULL,
  UserAccessType VARCHAR(255) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (HospitalPersonnelID NULLS FIRST)
)

/* Table: Hospitals */
CREATE TABLE Hospitals (
  HospitalID INT NULL,
  OrganizationID INT NULL,
  LegislativeCountryCode VARCHAR(10) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (HospitalID NULLS FIRST)
)

/* Table: InspectionLogs */
CREATE TABLE InspectionLogs (
  InspectionLogID INT NULL,
  InspectionID INT NULL,
  Findings VARCHAR(MAX) NULL,
  IsCritical BIT NULL,
  IsFollowUpRequired BIT NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (InspectionLogID NULLS FIRST)
)

/* Table: Inspections */
CREATE TABLE Inspections (
  InspectionID INT NULL,
  TrialID INT NULL,
  InspectionType VARCHAR(50) NULL,
  InspectionDate TIMESTAMP NULL,
  SponsorTrialRoleID INT NULL,
  TrialPersonnelID INT NULL,
  EstimatedStartDateTime TIMESTAMP NULL,
  EstimatedEndDateTime TIMESTAMP NULL,
  ActualStartDateTime TIMESTAMP NULL,
  ActualEndDateTime TIMESTAMP NULL,
  PlannedDuration DOUBLE PRECISION NULL,
  ActualDuration DOUBLE PRECISION NULL,
  FindingsCount INT NULL,
  MajorFindings INT NULL,
  MinorFindings INT NULL,
  CriticalFindings INT NULL,
  FollowUpRequired BIT NULL,
  FollowUpDate TIMESTAMP NULL,
  FollowUpCompleted BIT NULL,
  ReportReceived BIT NULL,
  ReportDate TIMESTAMP NULL,
  ReportLocation VARCHAR(255) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (InspectionID NULLS FIRST)
)

/* Table: InspectionTypes */
CREATE TABLE InspectionTypes (
  InspectionType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(255) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (InspectionType NULLS FIRST)
)

/* Table: Milestones */
CREATE TABLE Milestones (
  MilestoneID INT NULL,
  TrialID INT NULL,
  MilestoneName VARCHAR(50) NULL,
  MilestoneType VARCHAR(50) NULL,
  PlannedDate TIMESTAMP NULL,
  ActualDate TIMESTAMP NULL,
  Status VARCHAR(50) NULL,
  InvolvesAuthorityID INT NULL,
  ResponsibleTrialRoleID INT NULL,
  Critical BIT NULL,
  Completed BIT NULL,
  TransitionPhaseCode VARCHAR(20) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (MilestoneID NULLS FIRST)
)

/* Table: MilestoneSteps */
CREATE TABLE MilestoneSteps (
  MilestoneStepID INT NULL,
  MilestoneID INT NULL,
  ActionCode VARCHAR(50) NULL,
  AuthorityStepID INT NULL,
  TrialRoleID INT NULL,
  ReferenceNumber VARCHAR(100) NULL,
  SubmittedDate TIMESTAMP NULL,
  ApprovedDate TIMESTAMP NULL,
  ExpiryDate TIMESTAMP NULL,
  DocumentationLocation VARCHAR(255) NULL,
  Status VARCHAR(50) NULL,
  Version VARCHAR(20) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (MilestoneStepID NULLS FIRST)
)

/* Table: MilestoneTypes */
CREATE TABLE MilestoneTypes (
  MilestoneType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (MilestoneType NULLS FIRST)
)

/* Table: OrganizationDepartments */
CREATE TABLE OrganizationDepartments (
  OrganizationDepartmentID INT NULL,
  OrganizationID INT NULL,
  DepartmentName VARCHAR(50) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (OrganizationDepartmentID NULLS FIRST)
)

/* Table: Organizations */
CREATE TABLE Organizations (
  OrganizationID INT NULL,
  OrganizationNumber VARCHAR(20) NULL,
  OrganizationName VARCHAR(50) NULL,
  CountryCode VARCHAR(10) NULL,
  Address VARCHAR(100) NULL,
  PostalCode VARCHAR(20) NULL,
  City VARCHAR(50) NULL,
  Phone VARCHAR(50) NULL,
  Email VARCHAR(50) NULL,
  Website VARCHAR(255) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (OrganizationID NULLS FIRST)
)

/* Table: PatientSchedules */
CREATE TABLE PatientSchedules (
  PatientScheduleID INT NULL,
  TrialID INT NULL,
  Description VARCHAR(MAX) NULL,
  Name VARCHAR(50) NULL,
  OffsetDays INT NULL,
  WindowBeforeDays INT NULL,
  WindowAfterDays INT NULL,
  AffectedByProtocolID INT NULL,
  Required BIT NULL,
  Instructions VARCHAR(MAX) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (PatientScheduleID NULLS FIRST)
)

/* Table: Persons */
CREATE TABLE Persons (
  PersonID INT NULL,
  FirstName VARCHAR(50) NULL,
  LastName VARCHAR(50) NULL,
  Title VARCHAR(50) NULL,
  CountryCode VARCHAR(10) NULL,
  Phone VARCHAR(50) NULL,
  Mobile VARCHAR(50) NULL,
  Email VARCHAR(50) NULL,
  Gender VARCHAR(20) NULL,
  BirthDate VARCHAR(50) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (PersonID NULLS FIRST)
)

/* Table: PhaseCodes */
CREATE TABLE PhaseCodes (
  PhaseCode VARCHAR(20) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (PhaseCode NULLS FIRST)
)

/* Table: Protocols */
CREATE TABLE Protocols (
  ProtocolID INT NULL,
  TrialID INT NULL,
  ProtocolReference VARCHAR(100) NULL,
  EffectiveDate TIMESTAMP NULL,
  ValidFromDate TIMESTAMP NULL,
  ValidToDate TIMESTAMP NULL,
  ProtocolDescription VARCHAR(MAX) NULL,
  DocumentID INT NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (ProtocolID NULLS FIRST)
)

/* Table: QualityManagementReviews */
CREATE TABLE QualityManagementReviews (
  QualityManagementReviewID INT NULL,
  TrialID INT NULL,
  ActivityType VARCHAR(50) NULL,
  ActivityDate TIMESTAMP NULL,
  PerformedByTrialPersonnelID INT NULL,
  Scope VARCHAR(MAX) NULL,
  Findings VARCHAR(MAX) NULL,
  Recommendations VARCHAR(MAX) NULL,
  ActionsRequired VARCHAR(MAX) NULL,
  ActionDueDate TIMESTAMP NULL,
  ActionCompletedDate TIMESTAMP NULL,
  ReportLocationDescription VARCHAR(50) NULL,
  ReportDocumentID INT NULL,
  IsResolved BIT NULL,
  ResolvedByTrialPersonnelID INT NULL,
  ResolvedDate TIMESTAMP NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (QualityManagementReviewID NULLS FIRST)
)

/* Table: RoleTypes */
CREATE TABLE RoleTypes (
  RoleType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (RoleType NULLS FIRST)
)

/* Table: SponsorPersonnel */
CREATE TABLE SponsorPersonnel (
  SponsorPersonnelID INT NULL,
  SponsorID INT NULL,
  PersonID INT NULL,
  StartDate TIMESTAMP NULL,
  EndDate TIMESTAMP NULL,
  Specialization VARCHAR(100) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (SponsorPersonnelID NULLS FIRST)
)

/* Table: Sponsors */
CREATE TABLE Sponsors (
  SponsorID INT NULL,
  OrganizationID INT NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (SponsorID NULLS FIRST)
)

/* Table: SystemFieldNameMappings */
CREATE TABLE SystemFieldNameMappings (
  Name VARCHAR(50) NOT NULL,
  TranslationValue VARCHAR(50) NULL,
  LanguageCode VARCHAR(50) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (Name NULLS FIRST)
)

/* Table: SystemLogs */
CREATE TABLE SystemLogs (
  UserName VARCHAR(50) NOT NULL,
  FormName VARCHAR(50) NULL,
  ControlName VARCHAR(255) NULL,
  Severity VARCHAR(255) NULL,
  LogMessage VARCHAR(255) NULL,
  LogData VARCHAR(MAX) NULL,
  LogDateTime TIMESTAMP NULL DEFAULT NOW()
)

/* Table: SystemTableNameMappings */
CREATE TABLE SystemTableNameMappings (
  Name VARCHAR(50) NOT NULL,
  TranslationValue VARCHAR(50) NULL,
  LanguageCode VARCHAR(50) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (Name NULLS FIRST)
)

/* Table: TrialDeviations */
CREATE TABLE TrialDeviations (
  DeviationID INT NULL,
  TrialID INT NULL,
  DeviationDate TIMESTAMP NULL,
  DetectedDate TIMESTAMP NULL,
  DeviationType VARCHAR(50) NULL,
  Severity VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  ImmediateAction VARCHAR(MAX) NULL,
  RootCause VARCHAR(MAX) NULL,
  CAPA VARCHAR(MAX) NULL,
  CAPADueDate TIMESTAMP NULL,
  CAPACompletedDate TIMESTAMP NULL,
  ReportedToRegionalEthicsCommittee BIT NULL,
  RegionalEthicsCommitteeReportDate TIMESTAMP NULL,
  ReportedToSponsor BIT NULL,
  SponsorReportDate TIMESTAMP NULL,
  ResponsibleTrialRoleID INT NULL,
  Status VARCHAR(50) NULL,
  ClosedDate TIMESTAMP NULL,
  ClosedByTrialPersonnelID INT NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (DeviationID NULLS FIRST)
)

/* Table: TrialPatients */
CREATE TABLE TrialPatients (
  PatientID INT NULL,
  TrialID INT NULL,
  PatientCode VARCHAR(50) NULL,
  ScreeningDate TIMESTAMP NULL,
  EnrollmentDate TIMESTAMP NULL,
  ApprovalDate TIMESTAMP NULL,
  CompletionDate TIMESTAMP NULL,
  WithdrawalDate TIMESTAMP NULL,
  PatientStatus VARCHAR(50) NULL,
  DisqualificationReason VARCHAR(MAX) NULL,
  AgeAtScreening INT NULL,
  Gender VARCHAR(20) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (PatientID NULLS FIRST)
)

/* Table: TrialPersonnel */
CREATE TABLE TrialPersonnel (
  TrialPersonnelID INT NULL,
  TrialID INT NULL,
  TrialPersonnelType VARCHAR(50) NULL,
  HospitalPersonnelID INT NULL,
  SponsorPersonnelID INT NULL,
  AuthorityPersonnelID INT NULL,
  IsPrimary BIT NULL,
  StartDate TIMESTAMP NULL,
  EndDate TIMESTAMP NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (TrialPersonnelID NULLS FIRST)
)

/* Table: TrialPersonnelTypes */
CREATE TABLE TrialPersonnelTypes (
  TrialPersonnelType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (TrialPersonnelType NULLS FIRST)
)

/* Table: TrialRoles */
CREATE TABLE TrialRoles (
  TrialRoleID INT NULL,
  TrialID INT NULL,
  TrialPersonnelID INT NULL,
  RoleType VARCHAR(50) NULL,
  IsPrimary BIT NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (TrialRoleID NULLS FIRST)
)

/* Table: Trials */
CREATE TABLE Trials (
  TrialID INT NULL,
  HospitalID INT NULL,
  SponsorID INT NULL,
  TrialType VARCHAR(50) NULL,
  TrialTitle VARCHAR(50) NULL,
  Indication VARCHAR(MAX) NULL,
  EudraCTNumber VARCHAR(50) NULL,
  ClinicalTrialsGovID VARCHAR(50) NULL,
  PlannedEnrollment INT NULL,
  ActualEnrollment INT NULL,
  NumberScreened INT NULL,
  NumberIncluded INT NULL,
  PlannedStartDate TIMESTAMP NULL,
  FirstPatientInDate TIMESTAMP NULL,
  LastPatientOutDate TIMESTAMP NULL,
  DatabaseLockDate TIMESTAMP NULL,
  ReportSentDate TIMESTAMP NULL,
  ArchivingDate TIMESTAMP NULL,
  OverallStatus VARCHAR(50) NULL,
  ProtocolVersion VARCHAR(20) NULL,
  CurrentProtocolID INT NULL,
  CurrentPhaseCode VARCHAR(20) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (TrialID NULLS FIRST)
)

/* Table: TrialTypes */
CREATE TABLE TrialTypes (
  TrialType VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  Instructions VARCHAR(MAX) NULL,
  Notes VARCHAR(MAX) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (TrialType NULLS FIRST)
)

/* Table: UserAccessTypes */
CREATE TABLE UserAccessTypes (
  UserAccessType VARCHAR(50) NOT NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(255) NULL,
  CreatedDate TIMESTAMP NULL,
  ModifiedDate TIMESTAMP NULL,
  CreatedBy VARCHAR(20) NULL,
  ModifiedBy VARCHAR(20) NULL,
  IsDeleted BIT NULL DEFAULT FALSE,
  PRIMARY KEY (UserAccessType NULLS FIRST)
)

/* ============================================ */ /* CREATE INDEXES */ /* ============================================ */
CREATE INDEX FK_AdverseEvents_ClosedByTrialPersonnel ON AdverseEvents(ClosedByTrialPersonnelID NULLS FIRST)

CREATE INDEX FK_AdverseEvents_EventType ON AdverseEvents(EventType NULLS FIRST)

CREATE INDEX FK_AdverseEvents_Trial ON AdverseEvents(TrialID NULLS FIRST)

CREATE INDEX FK_AdverseEvents_TrialPatient ON AdverseEvents(PatientID NULLS FIRST)

CREATE INDEX idx_AdverseEvents_EventDate ON AdverseEvents(EventDate NULLS FIRST)

CREATE INDEX idx_AdverseEvents_EventType ON AdverseEvents(EventType NULLS FIRST)

CREATE INDEX idx_AdverseEvents_TrialID ON AdverseEvents(TrialID NULLS FIRST)

CREATE INDEX FK_Authorities_AuthorityTypes ON Authorities(AuthorityType NULLS FIRST)

CREATE INDEX FK_Authorities_LegislationCountry ON Authorities(LegislationCountryCode NULLS FIRST)

CREATE INDEX FK_Authorities_Organizations ON Authorities(OrganizationID NULLS FIRST)

CREATE INDEX FK_AuthorityPersonnel_Authority ON AuthorityPersonnel(AuthorityID NULLS FIRST)

CREATE INDEX FK_AuthorityPersonnel_Person ON AuthorityPersonnel(PersonID NULLS FIRST)

CREATE INDEX FK_AuthoritySteps_Authority ON AuthoritySteps(AuthorityID NULLS FIRST)

CREATE INDEX FK_Documents_ApprovedByHospitalPersonnel ON Documents(ApprovedByHospitalPersonnelID NULLS FIRST)

CREATE INDEX FK_Documents_ApprovedBySponsorPersonnel ON Documents(ApprovedBySponsorPersonnelID NULLS FIRST)

CREATE INDEX FK_Documents_DocumentType ON Documents(DocumentType NULLS FIRST)

CREATE INDEX FK_Documents_Trial ON Documents(TrialID NULLS FIRST)

CREATE INDEX idx_Documents_DocumentType ON Documents(DocumentType NULLS FIRST)

CREATE INDEX idx_Documents_Status ON Documents(Status NULLS FIRST)

CREATE INDEX idx_Documents_TrialID ON Documents(TrialID NULLS FIRST)

CREATE INDEX FK_HospitalPersonnel_Hospitals ON HospitalPersonnel(HospitalID NULLS FIRST)

CREATE INDEX FK_HospitalPersonnel_Person ON HospitalPersonnel(PersonID NULLS FIRST)

CREATE INDEX FK_Hospital_CountryCodes ON Hospitals(LegislativeCountryCode NULLS FIRST)

CREATE INDEX FK_Hospital_Organizations ON Hospitals(OrganizationID NULLS FIRST)

CREATE INDEX FK_InspectionLogs_Inspection ON InspectionLogs(InspectionID NULLS FIRST)

CREATE INDEX FK_Inspections_InspectionTypes ON Inspections(InspectionType NULLS FIRST)

CREATE INDEX FK_Inspections_SponsorTrialRole ON Inspections(SponsorTrialRoleID NULLS FIRST)

CREATE INDEX FK_Inspections_Trial ON Inspections(TrialID NULLS FIRST)

CREATE INDEX FK_Inspections_TrialPersonnel ON Inspections(TrialPersonnelID NULLS FIRST)

CREATE INDEX idx_Inspections_InspectionDate ON Inspections(InspectionDate NULLS FIRST)

CREATE INDEX idx_Inspections_InspectionType ON Inspections(InspectionType NULLS FIRST)

CREATE INDEX idx_Inspections_TrialID ON Inspections(TrialID NULLS FIRST)

CREATE INDEX FK_Milestones_Authority ON Milestones(InvolvesAuthorityID NULLS FIRST)

CREATE INDEX FK_Milestones_MilestoneTypes ON Milestones(MilestoneType NULLS FIRST)

CREATE INDEX FK_Milestones_ResponsibleTrialRole ON Milestones(ResponsibleTrialRoleID NULLS FIRST)

CREATE INDEX FK_Milestones_TransitionPhaseCodes ON Milestones(TransitionPhaseCode NULLS FIRST)

CREATE INDEX FK_Milestones_Trial ON Milestones(TrialID NULLS FIRST)

CREATE INDEX idx_Milestones_MilestoneType ON Milestones(MilestoneType NULLS FIRST)

CREATE INDEX idx_Milestones_PlannedDate ON Milestones(PlannedDate NULLS FIRST)

CREATE INDEX idx_Milestones_Status ON Milestones(Status NULLS FIRST)

CREATE INDEX idx_Milestones_TrialID ON Milestones(TrialID NULLS FIRST)

CREATE INDEX FK_MilestoneSteps_ActionCodes ON MilestoneSteps(ActionCode NULLS FIRST)

CREATE INDEX FK_MilestoneSteps_AuthorityStep ON MilestoneSteps(AuthorityStepID NULLS FIRST)

CREATE INDEX FK_MilestoneSteps_Milestone ON MilestoneSteps(MilestoneID NULLS FIRST)

CREATE INDEX FK_MilestoneSteps_TrialRole ON MilestoneSteps(TrialRoleID NULLS FIRST)

CREATE INDEX FK_OrganizationDepartment_Organizations ON OrganizationDepartments(OrganizationID NULLS FIRST)

CREATE INDEX FK_Organization_CountryCodes ON Organizations(CountryCode NULLS FIRST)

CREATE INDEX idx_Organization_CountryCodes ON Organizations(CountryCode NULLS FIRST)

CREATE INDEX FK_PatientSchedules_Protocol ON PatientSchedules(AffectedByProtocolID NULLS FIRST)

CREATE INDEX FK_PatientSchedules_Trial ON PatientSchedules(TrialID NULLS FIRST)

CREATE INDEX FK_Persons_CountryCodes ON Persons(CountryCode NULLS FIRST)

CREATE INDEX FK_Protocols_Document ON Protocols(DocumentID NULLS FIRST)

CREATE INDEX FK_Protocols_Trial ON Protocols(TrialID NULLS FIRST)

CREATE INDEX FK_QualityManagementLogs_ReportDocument ON QualityManagementReviews(ReportDocumentID NULLS FIRST)

CREATE INDEX FK_QualityManagementLogs_ResolvedByTrialPersonnel ON QualityManagementReviews(ResolvedByTrialPersonnelID NULLS FIRST)

CREATE INDEX FK_QualityManagementLogs_Trial ON QualityManagementReviews(TrialID NULLS FIRST)

CREATE INDEX FK_QualityManagementLogs_TrialPersonnel ON QualityManagementReviews(PerformedByTrialPersonnelID NULLS FIRST)

CREATE INDEX idx_QualityManagementLogs_ActivityType ON QualityManagementReviews(ActivityType NULLS FIRST)

CREATE INDEX idx_QualityManagementLogs_TrialID ON QualityManagementReviews(TrialID NULLS FIRST)

CREATE INDEX FK_SponsorPersonnel_Person ON SponsorPersonnel(PersonID NULLS FIRST)

CREATE INDEX FK_SponsorPersonnel_Sponsor ON SponsorPersonnel(SponsorID NULLS FIRST)

CREATE INDEX FK_Sponsors_Organizations ON Sponsors(OrganizationID NULLS FIRST)

CREATE INDEX FK_TrialDeviations_DeviationTypes ON TrialDeviations(DeviationType NULLS FIRST)

CREATE INDEX FK_TrialDeviations_ResponsibleTrialRole ON TrialDeviations(ResponsibleTrialRoleID NULLS FIRST)

CREATE INDEX FK_TrialDeviations_Trial ON TrialDeviations(TrialID NULLS FIRST)

CREATE INDEX idx_TrialDeviations_DeviationDate ON TrialDeviations(DeviationDate NULLS FIRST)

CREATE INDEX idx_TrialDeviations_Status ON TrialDeviations(Status NULLS FIRST)

CREATE INDEX idx_TrialDeviations_TrialID ON TrialDeviations(TrialID NULLS FIRST)

CREATE INDEX FK_TrialPatients_Trial ON TrialPatients(TrialID NULLS FIRST)

CREATE INDEX idx_TrialPatients_PatientStatus ON TrialPatients(PatientStatus NULLS FIRST)

CREATE INDEX idx_TrialPatients_TrialID ON TrialPatients(TrialID NULLS FIRST)

CREATE INDEX FK_TrialPersonnel_AuthorityPersonnel ON TrialPersonnel(AuthorityPersonnelID NULLS FIRST)

CREATE INDEX FK_TrialPersonnel_HospitalPersonnel ON TrialPersonnel(HospitalPersonnelID NULLS FIRST)

CREATE INDEX FK_TrialPersonnel_SponsorPersonnel ON TrialPersonnel(SponsorPersonnelID NULLS FIRST)

CREATE INDEX FK_TrialPersonnel_Trial ON TrialPersonnel(TrialID NULLS FIRST)

CREATE INDEX FK_TrialPersonnel_TrialPersonnelType ON TrialPersonnel(TrialPersonnelType NULLS FIRST)

CREATE INDEX idx_TrialPersonnel_TrialID ON TrialPersonnel(TrialID NULLS FIRST)

CREATE INDEX idx_TrialPersonnel_TrialPersonnelType ON TrialPersonnel(TrialPersonnelType NULLS FIRST)

CREATE INDEX FK_TrialRoles_RoleType ON TrialRoles(RoleType NULLS FIRST)

CREATE INDEX FK_TrialRoles_Trial ON TrialRoles(TrialID NULLS FIRST)

CREATE INDEX FK_TrialRoles_TrialPersonnel ON TrialRoles(TrialPersonnelID NULLS FIRST)

CREATE INDEX idx_TrialRoles_RoleType ON TrialRoles(RoleType NULLS FIRST)

CREATE INDEX idx_TrialRoles_TrialID ON TrialRoles(TrialID NULLS FIRST)

CREATE INDEX idx_TrialRoles_TrialPersonnelID ON TrialRoles(TrialPersonnelID NULLS FIRST)

CREATE INDEX FK_Trials_CurrentPhaseCodes ON Trials(CurrentPhaseCode NULLS FIRST)

CREATE INDEX FK_Trials_CurrentProtocol ON Trials(CurrentProtocolID NULLS FIRST)

CREATE INDEX FK_Trials_Hospitals ON Trials(HospitalID NULLS FIRST)

CREATE INDEX FK_Trials_Sponsor ON Trials(SponsorID NULLS FIRST)

CREATE INDEX FK_Trials_TrialTypes ON Trials(TrialType NULLS FIRST)

CREATE INDEX idx_Trials_CurrentPhaseCodes ON Trials(CurrentPhaseCode NULLS FIRST)

CREATE INDEX idx_Trials_HospitalID ON Trials(HospitalID NULLS FIRST)

CREATE INDEX idx_Trials_OverallStatus ON Trials(OverallStatus NULLS FIRST)

CREATE INDEX idx_Trials_PlannedStartDate ON Trials(PlannedStartDate NULLS FIRST)

CREATE INDEX idx_Trials_SponsorID ON Trials(SponsorID NULLS FIRST)

CREATE INDEX idx_Trials_TrialType ON Trials(TrialType NULLS FIRST)

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