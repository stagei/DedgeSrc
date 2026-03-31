CREATE TABLE TestTable (
    id INT PRIMARY KEY,
    name VARCHAR(100)
);

CREATE INDEX [idx_test] ON [TestTable] ([name]);

