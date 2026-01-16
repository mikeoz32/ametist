require "./spec_helper"
require "../src/movie"

describe Movie::Future do
  it "completes successfully and awakens waiters" do
    promise = Movie::Promise(Int32).new
    future = promise.future
    called = 0

    future.on_complete do |res|
      res.success?.should be_true
      res.value.should eq 5
      called += 1
    end

    promise.success(5)

    future.await.should eq 5
    called.should eq 1
  end

  it "invokes callbacks registered after completion" do
    promise = Movie::Promise(Int32).new
    future = promise.future

    promise.success(7)

    called = 0
    future.on_complete do |res|
      res.success?.should be_true
      res.value.should eq 7
      called += 1
    end

    called.should eq 1
  end

  it "propagates failure and on_failure" do
    promise = Movie::Promise(Int32).new
    future = promise.future
    error = RuntimeError.new("boom")

    future.on_failure do |err|
      err.should eq error
    end

    promise.failure(error)

    expect_raises(RuntimeError) { future.await }
  end

  it "propagates cancellation and on_cancel" do
    promise = Movie::Promise(Int32).new
    future = promise.future
    called = 0

    future.on_cancel do
      called += 1
    end

    promise.cancel

    expect_raises(Movie::FutureCancelled) { future.await }
    called.should eq 1
  end

  it "prevents double completion" do
    promise = Movie::Promise(Int32).new
    future = promise.future

    promise.success(1)
    promise.try_success(2).should be_false
    promise.try_failure(RuntimeError.new("nope")).should be_false
    promise.try_cancel.should be_false

    future.await.should eq 1
  end

  it "allows cancelling subscriptions" do
    promise = Movie::Promise(Int32).new
    future = promise.future
    called = 0

    sub = future.on_success { |_v| called += 1 }
    sub.cancel

    promise.success(10)
    called.should eq 0
  end
end
