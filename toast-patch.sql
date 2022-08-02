-- Disable TOAST compression on all newly created columsn
-- setting the column stroage to external.
-- See https://dba.stackexchange.com/a/315067/38877
-- for further discussion.

-- Sets number column to use external storage instead of MAIN
UPDATE pg_catalog.pg_type SET typstorage = 'e' WHERE typstorage = 'm';

-- Sets most of column types column to use external storage intead of EXTENDED
UPDATE pg_catalog.pg_type SET typstorage = 'e' WHERE typstorage = 'm';
