# Ratomic

Ratomic provides mutable data structures for use with Ruby's Ractors.
This allows Ruby code to scale beyond the infamous GVL.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add ratomic
```

## Usage

Ratomic provides several usæful structures:

### `Ratomic::Counter`

```ruby
c = Ratomic::Counter.new
c.read # => 0
c.increment
c.read # => 1
```

### `Ratomic::Queue`

A multi-producer, multi-consumer queue.

```ruby
q = Ratomic::Queue.new
q.push(Object.new)
q.pop # => <Object>
```

## License

[MIT License](https://opensource.org/licenses/MIT).
