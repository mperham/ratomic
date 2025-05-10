# Ratomic

Ratomic provides mutable data structures for use with Ruby's Ractors.
This allows Ruby code to scale beyond the infamous GVL.

# HELP WANTED!

> If you know Rust and Ruby C-extensions, we need your help!
> This project is brand new and could use your knowledge!
> If you don't know Rust or C, consider this a challenge to learn and solve.
> Read through the [issues](//github.com/mperham/ratomic/issues) to find work that sounds interesting to you.

## How to contribute

Please make sure to understand our [Code of Conduct](./CODE_OF_CONDUCT.md).

After changing code, you can give it a spin with:

```bash
rake
```

This should compile the Rust code and run all tests.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add ratomic
```

TODO: We have not released a gem yet.

## Usage

Ratomic provides several useful Ractor-safe structures.
Note the APIs available are frequently very limited compared to Ruby's broad API.

These structures are designed for use as class-level constants so they can be shared by numerous Ractors.

### `Ratomic::Counter`

```ruby
c = Ratomic::Counter.new
c.read # => 0
c.inc
c.inc(5)
c.dec(1)
c.dec
c.read # => 4
```

### `Ratomic::Pool`

A Ractor-safe object pool:

```ruby
POOL = Ratomic::Pool.new(5, 1.0) { Object.new }
POOL.with do |obj|
  # do something with obj
end
```

### `Ratomic::Map`

A Ractor-safe map/hash structure:

```ruby
HASH = Ratomic::Map.new
HASH["mike"] = 123
HASH["mike"] # => 123
HASH.fetch_and_modify(key) {|value| v + 1 }
HASH.clear
```

### `Ratomic::Queue`

A multi-producer, multi-consumer queue.

```ruby
q = Ratomic::Queue.new(128) # capacity must be a power of 2 and at least 2

q.push("hello")
q.push("world")

q.size     # => 2
q.empty?   # => false
q.peek     # => "hello"
item = q.pop # => "hello"
item = q.pop # => "world"
q.empty?   # => true
```
The `.new(capacity)` method initializes the queue with a fixed-size buffer. The capacity must be a power of 2 and at least 2, which ensures efficient indexing and wrap-around in the underlying buffer

Since `Ratomic::Queue` is a concurrent queue, the `size`, `empty?`, and `peek` methods provide only a best-effort guess — the values they return might be stale or incorrect.

## Thanks

[Ilya Bylich](https://github.com/iliabylich) wrote and documented his original research at [Ruby, Ractors, and Lock-free Data Structures/](https://iliabylich.github.io/ruby-ractors-and-lock-free-data-structures/).
Thank you for your impressive work, Ilya!

This repo is further research into the usability and limitations of Ractor-friendly structures in Ruby code and gems.

## License

[MIT License](https://opensource.org/licenses/MIT).
