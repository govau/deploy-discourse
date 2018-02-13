# Deploy discourse on cloud.gov.au

https://github.com/discourse/discourse

## Initial one-off setup

We assume you have already targeted the application space e.g. `cf target -o myorg -s discourse`.

### Add services to the space

Create discourse-postgres and discourse-redis services e.g.
```
cf create-service postgres myplan discourse-postgres
cf create-service redis32 myplan discourse-redis
```

Enable the required extensions in postgres e.g.
```
cf update-service discourse-postgres -c '{"extensions":["hstore", "pg_trgm"]}'
```

Create user-provided-service with other secrets by renaming secrets.sample.json to secrets.json (gitignored), adding your secrets, and then running
```
cf cups discourse-ups -p ./secrets.json
```

If you modify the secrets.json, you can update the service with
```
cf uups discourse-ups -p ./secrets.json
```
