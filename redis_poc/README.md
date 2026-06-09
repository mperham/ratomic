# Redis POC

Small local scripts that exercise `Ratomic::Map`, `Ratomic::Counter`, and
`Ratomic::LocalPool` with Redis clients under Thread and Ractor workloads.

`LocalPool` is used instead of `Ratomic::Pool` because Redis clients are
live I/O resources. They should be created and reused inside the Ractor that
owns them, not moved between Ractors.

Start Redis from the repo root:

```sh
docker compose up -d redis
```

Install the POC bundle:

```sh
cd redis_poc
bundle install
```

Run the basic movement script:

```sh
bundle exec ruby basic_redis.rb
```

Run the producer/consumer queue script with Threads or Ractors:

```sh
TYPE=Thread bundle exec ruby queue_redis.rb
TYPE=Ractor bundle exec ruby queue_redis.rb
```

Useful knobs:

```sh
TIMES=50000 PRODUCERS=4 CONSUMERS=8 POOL_SIZE=8 TYPE=Ractor bundle exec ruby queue_redis.rb
```

Use a different Redis host with:

```sh
REDIS_HOST=redis.example.test bundle exec ruby basic_redis.rb
```


## Smoke-test snapshot

These scripts are demonstrations and smoke tests, not formal benchmarks. They
exist to show that live Redis clients remain local to the Ractor that created
them.

A successful `basic_redis.rb` run looked like this:

```text
Thread
[{"one" => 31501}, {"two" => 31379}, {"three" => 31320}, {"four" => 31410}, {"five" => 31454}]

Ractor
[{"one" => 42419}, {"two" => 42186}, {"three" => 42400}, {"four" => 42206}, {"five" => 42568}]
```

A successful `queue_redis.rb` Ractor run looked like this:

```text
[:start, Ractor, 2026-06-10 01:17:57.584727984 +0800]
[[:producer_done, 0], [:producer_done, 1]]
[[:consumer_done, 0, 7998], [:consumer_done, 1, 7987], [:consumer_done, 2, 7984], [:consumer_done, 3, 8035], [:consumer_done, 4, 7996]]
[{"one" => 0}, {"two" => 0}, {"three" => 0}, {"four" => 0}, {"five" => 0}]
[:end, 2026-06-10 01:18:02.226310862 +0800]
```

Interpretation:

- no `Ractor::MovedError`
- no `Ractor::IsolationError`
- all produced queue items were consumed
- Redis queues drained to zero
- the `LocalPool` facade was shared, while Redis clients stayed local

## Inception note

`LocalPool` is intentionally a small "inception pool":

```text
pool facade
  ↓
local pool
  ↓
resource
```

That shape later maps naturally to hybrid runtimes where parallel workers own
local concurrent resource pools.
