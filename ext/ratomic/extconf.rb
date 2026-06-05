# frozen_string_literal: true

require "mkmf"
require "rb_sys/mkmf"

ENV["RUST_MIN_STACK"] ||= "33554432"

create_rust_makefile("ratomic/ratomic")
