-- Adding column to AdverseEvents: CreatedDate
ALTER TABLE AdverseEvents ADD COLUMN CreatedDate DATETIME NOT NULL;

-- Adding column to AdverseEvents: ModifiedBy
ALTER TABLE AdverseEvents ADD COLUMN ModifiedBy VARCHAR(255) NOT NULL;

-- Adding column to AdverseEvents: IsDeleted
ALTER TABLE AdverseEvents ADD COLUMN IsDeleted BIT NOT NULL DEFAULT FALSE;

-- Adding column to AdverseEvents: ModifiedDate
ALTER TABLE AdverseEvents ADD COLUMN ModifiedDate DATETIME NOT NULL;

-- Adding column to AdverseEvents: CreatedBy
ALTER TABLE AdverseEvents ADD COLUMN CreatedBy VARCHAR(255) NOT NULL;