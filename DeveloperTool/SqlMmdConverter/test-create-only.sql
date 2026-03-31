CREATE TABLES
-- ============================================

-- Table: ActionCodes
CREATE TABLE [ActionCodes] (
    [ActionCode] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([ActionCode])
);

CREATE TABLE [AdverseEvents] (
    [EventID] INT NULL,
    [TrialID] INT NULL,
    [EventType] NVARCHAR(50) NULL,
    [EventDate] DATETIME NULL,
    [DetectedDate] DATETIME NULL,
    [ReportDate] DATETIME NULL,
    [PatientID] INT NULL,
    [EventDescription] NVARCHAR(MAX) NULL,
    [Severity] NVARCHAR(MAX) NULL,
    [Seriousness] NVARCHAR(MAX) NULL,
    [Causality] NVARCHAR(MAX) NULL,
    [Outcome] NVARCHAR(MAX) NULL,
    [ActionTaken] NVARCHAR(MAX) NULL,
    [ReportedToRegionalEthicsCommittee] BIT NULL,
    [RegionalEthicsCommitteeReportDate] DATETIME NULL,
    [ReportedToSLV] BIT NULL,
    [SLVReportDate] DATETIME NULL,
    [ReportedToSponsor] BIT NULL,
    [SponsorReportDate] DATETIME NULL,
    [FollowUpRequired] BIT NULL,
    [StatusDescription] NVARCHAR(MAX) NULL,
    [ClosedDate] DATETIME NULL,
    [ClosedByTrialPersonnelID] INT NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([EventID])
);

CREATE TABLE [Authorities] (
    [AuthorityID] INT NULL,
    [AuthorityType] NVARCHAR(50) NULL,
    [LegislationCountryCode] NVARCHAR(10) NULL,
    [OrganizationID] INT NULL,
    [LongName] NVARCHAR(50) NULL,
    [AbbriviationName] NVARCHAR(50) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([AuthorityID])
);

CREATE TABLE [AuthorityPersonnel] (
    [AuthorityPersonnelID] INT NULL,
    [AuthorityID] INT NULL,
    [PersonID] INT NULL,
    [StartDate] DATETIME NULL,
    [EndDate] DATETIME NULL,
    [Specialization] NVARCHAR(100) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([AuthorityPersonnelID])
);

CREATE TABLE [AuthoritySteps] (
    [AuthorityStepID] INT NULL,
    [AuthorityID] INT NULL,
    [OrderIndex] INT NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [WindowBeforeDays] INT NULL,
    [WindowAfterDays] INT NULL,
    [Required] BIT NULL,
    [Instructions] NVARCHAR(MAX) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([AuthorityStepID])
);

CREATE TABLE [AuthorityTypes] (
    [AuthorityType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([AuthorityType])
);

CREATE TABLE [CountryCodes] (
    [CountryCode] NVARCHAR(10) NULL,
    [Name] NVARCHAR(50) NULL,
    [PhoneCountryCode] NVARCHAR(10) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([CountryCode])
);

CREATE TABLE [DeviationTypes] (
    [DeviationType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(255) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([DeviationType])
);

CREATE TABLE [Documents] (
    [DocumentID] INT NULL,
    [TrialID] INT NULL,
    [DocumentType] NVARCHAR(50) NULL,
    [DocumentName] NVARCHAR(255) NULL,
    [Description] NVARCHAR(255) NULL,
    [Version] NVARCHAR(20) NULL,
    [DocumentDate] DATETIME NULL,
    [ApprovedDate] DATETIME NULL,
    [ApprovedBySponsorPersonnelID] INT NULL,
    [ApprovedByHospitalPersonnelID] INT NULL,
    [DocumentLocation] NVARCHAR(255) NULL,
    [FilePath] NVARCHAR(255) NULL,
    [FileFormat] NVARCHAR(20) NULL,
    [Status] NVARCHAR(50) NULL,
    [IsCurrent] BIT NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([DocumentID])
);

CREATE TABLE [DocumentTypes] (
    [DocumentType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([DocumentType])
);

CREATE TABLE [EventTypes] (
    [EventType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(255) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([EventType])
);

CREATE TABLE [HospitalPersonnel] (
    [HospitalPersonnelID] INT NULL,
    [HospitalID] INT NULL,
    [PersonID] INT NULL,
    [StartDate] DATETIME NULL,
    [EndDate] DATETIME NULL,
    [Specialization] NVARCHAR(100) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [UserAccessType] NVARCHAR(255) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([HospitalPersonnelID])
);

CREATE TABLE [Hospitals] (
    [HospitalID] INT NULL,
    [OrganizationID] INT NULL,
    [LegislativeCountryCode] NVARCHAR(10) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([HospitalID])
);

CREATE TABLE [InspectionLogs] (
    [InspectionLogID] INT NULL,
    [InspectionID] INT NULL,
    [Findings] NVARCHAR(MAX) NULL,
    [IsCritical] BIT NULL,
    [IsFollowUpRequired] BIT NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([InspectionLogID])
);

CREATE TABLE [Inspections] (
    [InspectionID] INT NULL,
    [TrialID] INT NULL,
    [InspectionType] NVARCHAR(50) NULL,
    [InspectionDate] DATETIME NULL,
    [SponsorTrialRoleID] INT NULL,
    [TrialPersonnelID] INT NULL,
    [EstimatedStartDateTime] DATETIME NULL,
    [EstimatedEndDateTime] DATETIME NULL,
    [ActualStartDateTime] DATETIME NULL,
    [ActualEndDateTime] DATETIME NULL,
    [PlannedDuration] DOUBLE NULL,
    [ActualDuration] DOUBLE NULL,
    [FindingsCount] INT NULL,
    [MajorFindings] INT NULL,
    [MinorFindings] INT NULL,
    [CriticalFindings] INT NULL,
    [FollowUpRequired] BIT NULL,
    [FollowUpDate] DATETIME NULL,
    [FollowUpCompleted] BIT NULL,
    [ReportReceived] BIT NULL,
    [ReportDate] DATETIME NULL,
    [ReportLocation] NVARCHAR(255) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([InspectionID])
);

CREATE TABLE [InspectionTypes] (
    [InspectionType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(255) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([InspectionType])
);

CREATE TABLE [Milestones] (
    [MilestoneID] INT NULL,
    [TrialID] INT NULL,
    [MilestoneName] NVARCHAR(50) NULL,
    [MilestoneType] NVARCHAR(50) NULL,
    [PlannedDate] DATETIME NULL,
    [ActualDate] DATETIME NULL,
    [Status] NVARCHAR(50) NULL,
    [InvolvesAuthorityID] INT NULL,
    [ResponsibleTrialRoleID] INT NULL,
    [Critical] BIT NULL,
    [Completed] BIT NULL,
    [TransitionPhaseCode] NVARCHAR(20) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([MilestoneID])
);

CREATE TABLE [MilestoneSteps] (
    [MilestoneStepID] INT NULL,
    [MilestoneID] INT NULL,
    [ActionCode] NVARCHAR(50) NULL,
    [AuthorityStepID] INT NULL,
    [TrialRoleID] INT NULL,
    [ReferenceNumber] NVARCHAR(100) NULL,
    [SubmittedDate] DATETIME NULL,
    [ApprovedDate] DATETIME NULL,
    [ExpiryDate] DATETIME NULL,
    [DocumentationLocation] NVARCHAR(255) NULL,
    [Status] NVARCHAR(50) NULL,
    [Version] NVARCHAR(20) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([MilestoneStepID])
);

CREATE TABLE [MilestoneTypes] (
    [MilestoneType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([MilestoneType])
);

CREATE TABLE [OrganizationDepartments] (
    [OrganizationDepartmentID] INT NULL,
    [OrganizationID] INT NULL,
    [DepartmentName] NVARCHAR(50) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([OrganizationDepartmentID])
);

CREATE TABLE [Organizations] (
    [OrganizationID] INT NULL,
    [OrganizationNumber] NVARCHAR(20) NULL,
    [OrganizationName] NVARCHAR(50) NULL,
    [CountryCode] NVARCHAR(10) NULL,
    [Address] NVARCHAR(100) NULL,
    [PostalCode] NVARCHAR(20) NULL,
    [City] NVARCHAR(50) NULL,
    [Phone] NVARCHAR(50) NULL,
    [Email] NVARCHAR(50) NULL,
    [Website] NVARCHAR(255) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([OrganizationID])
);

CREATE TABLE [PatientSchedules] (
    [PatientScheduleID] INT NULL,
    [TrialID] INT NULL,
    [Description] NVARCHAR(MAX) NULL,
    [Name] NVARCHAR(50) NULL,
    [OffsetDays] INT NULL,
    [WindowBeforeDays] INT NULL,
    [WindowAfterDays] INT NULL,
    [AffectedByProtocolID] INT NULL,
    [Required] BIT NULL,
    [Instructions] NVARCHAR(MAX) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([PatientScheduleID])
);

CREATE TABLE [Persons] (
    [PersonID] INT NULL,
    [FirstName] NVARCHAR(50) NULL,
    [LastName] NVARCHAR(50) NULL,
    [Title] NVARCHAR(50) NULL,
    [CountryCode] NVARCHAR(10) NULL,
    [Phone] NVARCHAR(50) NULL,
    [Mobile] NVARCHAR(50) NULL,
    [Email] NVARCHAR(50) NULL,
    [Gender] NVARCHAR(20) NULL,
    [BirthDate] NVARCHAR(50) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([PersonID])
);

CREATE TABLE [PhaseCodes] (
    [PhaseCode] NVARCHAR(20) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([PhaseCode])
);

CREATE TABLE [Protocols] (
    [ProtocolID] INT NULL,
    [TrialID] INT NULL,
    [ProtocolReference] NVARCHAR(100) NULL,
    [EffectiveDate] DATETIME NULL,
    [ValidFromDate] DATETIME NULL,
    [ValidToDate] DATETIME NULL,
    [ProtocolDescription] NVARCHAR(MAX) NULL,
    [DocumentID] INT NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([ProtocolID])
);

CREATE TABLE [QualityManagementReviews] (
    [QualityManagementReviewID] INT NULL,
    [TrialID] INT NULL,
    [ActivityType] NVARCHAR(50) NULL,
    [ActivityDate] DATETIME NULL,
    [PerformedByTrialPersonnelID] INT NULL,
    [Scope] NVARCHAR(MAX) NULL,
    [Findings] NVARCHAR(MAX) NULL,
    [Recommendations] NVARCHAR(MAX) NULL,
    [ActionsRequired] NVARCHAR(MAX) NULL,
    [ActionDueDate] DATETIME NULL,
    [ActionCompletedDate] DATETIME NULL,
    [ReportLocationDescription] NVARCHAR(50) NULL,
    [ReportDocumentID] INT NULL,
    [IsResolved] BIT NULL,
    [ResolvedByTrialPersonnelID] INT NULL,
    [ResolvedDate] DATETIME NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([QualityManagementReviewID])
);

CREATE TABLE [RoleTypes] (
    [RoleType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([RoleType])
);

CREATE TABLE [SponsorPersonnel] (
    [SponsorPersonnelID] INT NULL,
    [SponsorID] INT NULL,
    [PersonID] INT NULL,
    [StartDate] DATETIME NULL,
    [EndDate] DATETIME NULL,
    [Specialization] NVARCHAR(100) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([SponsorPersonnelID])
);

CREATE TABLE [Sponsors] (
    [SponsorID] INT NULL,
    [OrganizationID] INT NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([SponsorID])
);

CREATE TABLE [SystemFieldNameMappings] (
    [Name] NVARCHAR(50) NOT NULL,
    [TranslationValue] NVARCHAR(50) NULL,
    [LanguageCode] NVARCHAR(50) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([Name])
);

CREATE TABLE [SystemLogs] (
    [UserName] NVARCHAR(50) NOT NULL,
    [FormName] NVARCHAR(50) NULL,
    [ControlName] NVARCHAR(255) NULL,
    [Severity] NVARCHAR(255) NULL,
    [LogMessage] NVARCHAR(255) NULL,
    [LogData] NVARCHAR(MAX) NULL,
    [LogDateTime] DATETIME NULL DEFAULT =Now()
);

CREATE TABLE [SystemTableNameMappings] (
    [Name] NVARCHAR(50) NOT NULL,
    [TranslationValue] NVARCHAR(50) NULL,
    [LanguageCode] NVARCHAR(50) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([Name])
);

CREATE TABLE [TrialDeviations] (
    [DeviationID] INT NULL,
    [TrialID] INT NULL,
    [DeviationDate] DATETIME NULL,
    [DetectedDate] DATETIME NULL,
    [DeviationType] NVARCHAR(50) NULL,
    [Severity] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [ImmediateAction] NVARCHAR(MAX) NULL,
    [RootCause] NVARCHAR(MAX) NULL,
    [CAPA] NVARCHAR(MAX) NULL,
    [CAPADueDate] DATETIME NULL,
    [CAPACompletedDate] DATETIME NULL,
    [ReportedToRegionalEthicsCommittee] BIT NULL,
    [RegionalEthicsCommitteeReportDate] DATETIME NULL,
    [ReportedToSponsor] BIT NULL,
    [SponsorReportDate] DATETIME NULL,
    [ResponsibleTrialRoleID] INT NULL,
    [Status] NVARCHAR(50) NULL,
    [ClosedDate] DATETIME NULL,
    [ClosedByTrialPersonnelID] INT NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([DeviationID])
);

CREATE TABLE [TrialPatients] (
    [PatientID] INT NULL,
    [TrialID] INT NULL,
    [PatientCode] NVARCHAR(50) NULL,
    [ScreeningDate] DATETIME NULL,
    [EnrollmentDate] DATETIME NULL,
    [ApprovalDate] DATETIME NULL,
    [CompletionDate] DATETIME NULL,
    [WithdrawalDate] DATETIME NULL,
    [PatientStatus] NVARCHAR(50) NULL,
    [DisqualificationReason] NVARCHAR(MAX) NULL,
    [AgeAtScreening] INT NULL,
    [Gender] NVARCHAR(20) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([PatientID])
);

CREATE TABLE [TrialPersonnel] (
    [TrialPersonnelID] INT NULL,
    [TrialID] INT NULL,
    [TrialPersonnelType] NVARCHAR(50) NULL,
    [HospitalPersonnelID] INT NULL,
    [SponsorPersonnelID] INT NULL,
    [AuthorityPersonnelID] INT NULL,
    [IsPrimary] BIT NULL,
    [StartDate] DATETIME NULL,
    [EndDate] DATETIME NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([TrialPersonnelID])
);

CREATE TABLE [TrialPersonnelTypes] (
    [TrialPersonnelType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([TrialPersonnelType])
);

CREATE TABLE [TrialRoles] (
    [TrialRoleID] INT NULL,
    [TrialID] INT NULL,
    [TrialPersonnelID] INT NULL,
    [RoleType] NVARCHAR(50) NULL,
    [IsPrimary] BIT NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([TrialRoleID])
);

CREATE TABLE [Trials] (
    [TrialID] INT NULL,
    [HospitalID] INT NULL,
    [SponsorID] INT NULL,
    [TrialType] NVARCHAR(50) NULL,
    [TrialTitle] NVARCHAR(50) NULL,
    [Indication] NVARCHAR(MAX) NULL,
    [EudraCTNumber] NVARCHAR(50) NULL,
    [ClinicalTrialsGovID] NVARCHAR(50) NULL,
    [PlannedEnrollment] INT NULL,
    [ActualEnrollment] INT NULL,
    [NumberScreened] INT NULL,
    [NumberIncluded] INT NULL,
    [PlannedStartDate] DATETIME NULL,
    [FirstPatientInDate] DATETIME NULL,
    [LastPatientOutDate] DATETIME NULL,
    [DatabaseLockDate] DATETIME NULL,
    [ReportSentDate] DATETIME NULL,
    [ArchivingDate] DATETIME NULL,
    [OverallStatus] NVARCHAR(50) NULL,
    [ProtocolVersion] NVARCHAR(20) NULL,
    [CurrentProtocolID] INT NULL,
    [CurrentPhaseCode] NVARCHAR(20) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([TrialID])
);

CREATE TABLE [TrialTypes] (
    [TrialType] NVARCHAR(50) NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(MAX) NULL,
    [Instructions] NVARCHAR(MAX) NULL,
    [Notes] NVARCHAR(MAX) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([TrialType])
);

CREATE TABLE [UserAccessTypes] (
    [UserAccessType] NVARCHAR(50) NOT NULL,
    [Name] NVARCHAR(50) NULL,
    [Description] NVARCHAR(255) NULL,
    [CreatedDate] DATETIME NULL,
    [ModifiedDate] DATETIME NULL,
    [CreatedBy] NVARCHAR(20) NULL,
    [ModifiedBy] NVARCHAR(20) NULL,
    [IsDeleted] BIT NULL DEFAULT False,
    PRIMARY KEY ([UserAccessType])
);
