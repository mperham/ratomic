# Redis POC

Small local scripts that exercise `Ratomic::Map`, `Ratomic::Counter`, and
`Ratomic::Pool` with Redis clients under Thread and Ractor workloads.

Start Redis from the repo root:

```sh
docker compose up -d redis
```

Install the POC bundle:

```sh
cd redis_poc
bundle install
```

Run the scripts:

```sh
bundle exec ruby basic_redis.rb
bundle exec ruby queue_redis.rb
```

Use a different Redis host with:

```sh
REDIS_HOST=redis.example.test bundle exec ruby basic_redis.rb
```
