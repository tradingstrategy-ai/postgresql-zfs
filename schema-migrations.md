# Schema migrations

Tuning PostgreSQL performance might mean tuning individual table or even column scheames

- Hand tuning and microo ptimising are hard to keep up with schma tools like [Alembic](https://alembic.sqlalchemy.org/en/latest/)

# Schema comparison and migration tools

[See this StackOverflow post](https://stackoverflow.com/a/4804866/315168).

# Liquibase

## Install Liquibase

[Download free CLI binary from here](https://docs.liquibase.com/install/home.html).

## Example liquibase ALTER TABLE statement script

```shell
set -e
set -x

PROD_USER=postgres
PROD_HOST=localhost
PROD_PASSWORD=$POSTGRES_PASSWORD
PROD_DATABASE=oracle_v2
PROD_PORT=5556
LOCAL_HOST=localhost
LOCAL_USER=postgres
LOCAL_PASSWORD=
LOCAL_DATABASE=
LOCAL_PORT=5555

if [ -z "$PROD_PASSWORD" ] ; then
  echo "PROD_PASSWORD missing, set $POSTGRES_PASSWORD env"
  exit 1
fi

CHANGELOG_SQL="prod-changelog.sql"

# Writes a change log file between two databases
# in ALTER TABLE SQL format
liquibase diff-changelog \
  --changelog-file=$CHANGELOG_SQL \
  --reference-url="jdbc:postgresql://$PROD_HOST:$PROD_PORT/$PROD_DATABASE?user=$PROD_USER&password=$PROD_PASSWORD" \
  --url="jdbc:postgresql://$LOCAL_HOST:$LOCAL_PORT/$LOCAL_DATABASE?user=$LOCAL_USER&password=$LOCAL_PASSWORD"


echo "See $CHANGELOG_SQL for details"


```

Then manually clean up migrations.sql and hack pick statements.

## Migra

**Note**: Migra does not handle index changes.

Do manually managed schema comparisons using [migra](https://github.com/djrobstep/migra)

### Install migra

[Install locally on your laptop](https://databaseci.com/docs/migra/installing-and-connecting).

- Python based, can be installed to the existing Python developer tool chain

### Diff between production optimisations and latest known managed state

- Create a new database with all Alembic migrations applied
- Compare this to the production database

Example that compares between SSH-tunneled production database a local development database.
Note that other PostgreSQL needs to be in non-standard port to not cause TCP/IP port conflicts. 

```shell
PROD_USER=
PROD_PASSWORD=
PROD_DATABASE=oracle_v2
PROD_PORT=5555
LOCAL_USER=dex_ohlcv
LOCAL_PASSWORD=dex_ohlcv
LOCAL_DATABASE=dex_ohlcv
LOCAL_PORT=5556
migra \
  "postgresql:///$PROD_USER:$PROD_PASSWORD@localhost:$PROD_PORT/$PROD_DATABASE" \
  "postgresql:///$LOCAL_USER:$LOCAL_PASSWORD@localhost:$LOCAL_PORT/LOCAL_DATABASE"
```

