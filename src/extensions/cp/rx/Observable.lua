--- === cp.rx.Observable ===
---
--- Observables push values to [Observers](cp.rx.Observer.md).

local require           = require

local List              = require "cp.collect.List"
local Queue             = require "cp.collect.Queue"

local Observer          = require "cp.rx.Observer"
local Reference         = require "cp.rx.Reference"
local TimeoutScheduler  = require "cp.rx.TimeoutScheduler"
local util              = require "cp.rx.util"

local format            = string.format
local insert            = table.insert
local remove            = table.remove

-- default to using the TimeoutScheduler
util.defaultScheduler(TimeoutScheduler.create())

local Observable = {}
Observable.__index = Observable
Observable.__tostring = util.constant('Observable')

--- cp.rx.Observable.is(thing) -> boolean
--- Function
--- Checks if the thing is an instance of [Observable](cp.rx.Observable.md).
---
--- Parameters:
---  * thing   - The thing to check.
---
--- Returns:
---  * `true` if the thing is an `Observable`.
function Observable.is(thing)
    return util.isa(thing, Observable)
end

--- cp.rx.Observable.create(onSubscription) -> cp.rx.Observable
--- Constructor
--- Creates a new Observable.
---
--- Parameters:
---  * onSubscription  - The reference function that produces values.
---
--- Returns:
---  * The new `Observable`.
function Observable.create(onSubscription)
  local self = {
    _subscribe = onSubscription
  }

  return setmetatable(self, Observable)
end

--- cp.rx.Observable:subscribe(observer [, onError[, onCompleted]]) -> cp.rx.Reference
--- Method
--- Shorthand for creating an [Observer](cp.rx.Observer.md) and passing it to this Observable's [subscription](#subscri) function.
---
--- Parameters:
---  * observer - Either an [Observer](cp.rx.Observer.md) or a `function` to be called when the Observable produces a value.
---  * onError - A `function` to be called when the Observable terminates due to an error.
---  * onCompleted - A 'function` to be called when the Observable completes normally.
---
--- Returns:
---  * A [Reference](cp.rx.Reference.md) which can be used to cancel the subscription.
function Observable:subscribe(onNext, onError, onCompleted)
  if Observer.is(onNext) then
    return self._subscribe(onNext)
  else
    return self._subscribe(Observer.create(onNext, onError, onCompleted))
  end
end

--- cp.rx.Observable.empty() -> cp.rx.Observable
--- Constructor
--- Returns an Observable that immediately completes without producing a value.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable.empty()
  return Observable.create(function(observer)
    observer:onCompleted()
  end)
end

--- cp.rx.Observable.never() -> cp.rx.Observable
--- Constructor
--- Returns an Observable that never produces values and never completes.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable.never()
  return Observable.create(function(_) end)
end

--- cp.rx.Observable.throw(message, ...) -> cp.rx.Observable
--- Constructor
--- Returns an Observable that immediately produces an error.
---
--- Parameters:
---  * message   - The message to send.
---  * ...       - The additional values to apply to the message, using `string.format` syntax.
---
--- Returns:
---  * The new `Observable`.
function Observable.throw(message, ...)
  if select("#", ...) > 0 then
    message = string.format(message, ...)
  end
  return Observable.create(function(observer)
    observer:onError(message)
  end)
end

--- cp.rx.Observable.of(...) -> cp.rx.Observable
--- Constructor
--- Creates an Observable that produces a set of values.
---
--- Parameters:
---  * ...     - The list of values to send as individual `onNext` values.
---
--- Returns:
---  * The new `Observable`.
function Observable.of(...)
  local args = {...}
  local argCount = select('#', ...)
  return Observable.create(function(observer)
    for i = 1, argCount do
      observer:onNext(args[i])
    end

    observer:onCompleted()
  end)
end

--- cp.rx.Observable.fromRange(initial[, limit[, step]]) -> cp.rx.Observable
--- Constructor
--- Creates an Observable that produces a range of values in a manner similar to a Lua `for` loop.
---
--- Parameters:
---  * initial   - The first value of the range, or the upper limit if no other arguments are specified.
---  * limit     - The second value of the range. Defaults to no limit.
---  * step      - An amount to increment the value by each iteration. Defaults to `1`.
---
--- Returns:
---  * The new `Observable`.
function Observable.fromRange(initial, limit, step)
  if not limit and not step then
    initial, limit = 1, initial
  end

  step = step or 1

  return Observable.create(function(observer)
    for i = initial, limit, step do
      observer:onNext(i)
    end

    observer:onCompleted()
  end)
end

--- cp.rx.Observable.fromTable(t, iterator, keys) -> cp.rx.Observable
--- Constructor
--- Creates an `Observable` that produces values from a table.
---
--- Parameters:
---  * t         - The `table` used to create the `Observable`.
---  * iterator  - An iterator used to iterate the table, e.g. `pairs` or `ipairs`. Defaults to `pairs`.
---  * keys      - If `true`, also emit the keys of the table. Defaults to `false`.
---
--- Returns:
---  * The new `Observable`.
function Observable.fromTable(t, iterator, keys)
  iterator = iterator or pairs
  return Observable.create(function(observer)
    for key, value in iterator(t) do
      if keys then
        observer:onNext(value, key)
      else
        observer:onNext(value)
      end
    end

    observer:onCompleted()
  end)
end

--- cp.rx.Observable.fromCoroutine(fn, scheduler) -> cp.rx.Observable
--- Constructor
--- Creates an Observable that produces values when the specified coroutine yields.
---
--- Parameters:
---  * fn - A `coroutine` or `function` to use to generate values.  Note that if a coroutine is used, the values it yields will be shared by all subscribed [Observers](cp.rx.Observer.md) (influenced by the [Scheduler](cp.rx.Scheduler.md)), whereas a new coroutine will be created for each Observer when a `function` is used.
---  * scheduler - The scheduler
---
--- Returns:
---  * The new `Observable`.
function Observable.fromCoroutine(fn, scheduler)
  scheduler = scheduler or util.defaultScheduler()
  return Observable.create(function(observer)
    local thread = type(fn) == 'function' and coroutine.create(fn) or fn
    return scheduler:schedule(function()
      while not observer.stopped do
        local success, value = coroutine.resume(thread)

        if success then
          observer:onNext(value)
        else
          return observer:onError(value)
        end

        if coroutine.status(thread) == 'dead' then
          return observer:onCompleted()
        end

        coroutine.yield()
      end
    end)
  end)
end

--- cp.rx.Observable.fromFileByLine(filename) -> cp.rx.Observable
--- Constructor
--- Creates an Observable that produces values from a file, line by line.
---
--- Parameters:
---  * filename - The name of the file used to create the Observable.
---
--- Returns:
---  * The new `Observable`.
function Observable.fromFileByLine(filename)
  return Observable.create(function(observer)
    local f = io.open(filename, 'r')
    if f
    then
      f:close()
      for line in io.lines(filename) do
        observer:onNext(line)
      end

      return observer:onCompleted()
    else
      return observer:onError(filename)
    end
  end)
end

--- cp.rx.Observable.defer(fn) -> cp.rx.Observable
--- Constructor
--- Creates an `Observable` that executes the `function` to create a new `Observable` each time an [Observer](cp.rx.Observer.md) subscribes.
---
--- Parameters:
---  * fn - A function that returns an `Observable`.
---
--- Returns:
---  * The new `Observable`.
function Observable.defer(fn)
  return setmetatable({
    subscribe = function(_, ...)
      local observable = fn()
      return observable:subscribe(...)
    end
  }, Observable)
end

--- cp.rx.Observable.replicate(value[, count]) -> cp.rx.Observable
--- Constructor
--- Creates an `Observable` that repeats a value a specified number of times.
---
--- Parameters:
---  * value - The value to repeat.
---  * count - The number of times to repeat the value.  If left unspecified, the value is repeated an infinite number of times.
---
--- Returns:
---  * The new `Observable`.
function Observable.replicate(value, count)
  return Observable.create(function(observer)
    while count == nil or count > 0 do
      observer:onNext(value)
      if count then
        count = count - 1
      end
    end
    observer:onCompleted()
  end)
end

--- cp.rx.Observable:dump(name, formatter)
--- Method
--- Subscribes to this Observable and prints values it produces.
---
--- Parameters:
---  * name      - Prefixes the printed messages with a name.
---  * formatter - A function that formats one or more values to be printed. Defaults to `tostring`.
---
--- Returns:
---  * A [Reference](cp.rx.Reference.md) for the subscription.
function Observable:dump(name, formatter)
  name = name and (name .. ' ') or ''
  formatter = formatter or tostring

  local onNext = function(...) print(format("%sonNext: %s", name, formatter(...))) end
  local onError = function(e) print(format("%sonError: %s", name, e)) end
  local onCompleted = function() print(format("%sonCompleted", name)) end

  return self:subscribe(onNext, onError, onCompleted)
end

--- cp.rx.Observable:all(predicate) -> cp.rx.Observable
--- Method
--- Determine whether all items emitted by an Observable meet some criteria.
---
--- Parameters:
---  * predicate - The predicate used to evaluate objects. Defaults to the `identity`.
---
--- Returns:
---  * A new `Observable`.
function Observable:all(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        local ok = util.tryWithObserver(observer, function(...)
          if not predicate(...) then
            done()
            observer:onNext(false)
            observer:onCompleted()
          end
        end, ...)
        if not ok then
          done()
        end
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onNext(true)
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable.firstEmitting(...) -> cp.rx.Observer
--- Constructor
--- Given a set of Observables, produces values from only the first one to produce a value or complete.
---
--- Parameters:
---  * ... - list of [Observables](cp.rx.Observable.md)
---
--- Returns:
---  * The new `Observable`.
function Observable.firstEmitting(a, b, ...)
  if not a or not b then return a end

  return Observable.create(function(observer)
    local referenceA, referenceB
    local active = true

    local function cancelA()
      if referenceA then referenceA:cancel() end
      referenceA = nil
    end

    local function cancelB()
      if referenceB then referenceB:cancel() end
      referenceB = nil
    end

    local function done()
      active = false
      cancelA()
      cancelB()
    end

    referenceA = a:subscribe(
      function(...)
        if active then
          cancelB()
          observer:onNext(...)
        end
      end,
      function(e)
        if active then
          done()
          observer:onError(e)
        end
      end,
      function()
        if active then
          done()
          observer:onCompleted()
        end
      end
    )

    referenceB = b:subscribe(
      function(...)
        if active then
          cancelA()
          observer:onNext(...)
        end
      end,
      function(e)
        if active then
          done()
          observer:onError(e)
        end
      end,
      function()
        if active then
          done()
          observer:onCompleted()
        end
      end
    )

    return Reference.create(done)
  end):firstEmitting(...)
end

--- cp.rx.Observable:average() -> cp.rx.Observable
--- Method
--- Returns an Observable that produces the average of all values produced by the original.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:average()
  return Observable.create(function(observer)
    local sum, count = 0, 0

    local function onNext(value)
      sum = sum + value
      count = count + 1
    end

    local function onError(e)
      observer:onError(e)
    end

    local function onCompleted()
      if count > 0 then
        observer:onNext(sum / count)
      end

      observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- cp.rx.Observable:buffer(size) -> cp.rx.Observable
--- Method
--- Returns an Observable that buffers values from the original and produces them as multiple values.
---
--- Parameters:
---  * size    - The size of the buffer.
---
--- Returns:
---  * The new `Observable`.
function Observable:buffer(size)
  return Observable.create(function(observer)
    local buffer = {}
    local active, ref = true, nil

    local function done()
      if active then
        active = false
        ref:cancel()
        ref = nil
        buffer = nil
      end
    end

    local function emit()
      if #buffer > 0 then
        observer:onNext(util.unpack(buffer))
        buffer = {}
      end
    end

    local function onNext(...)
      local values = util.pack(...)
      for i = 1, #values do
        insert(buffer, values[i])
        if #buffer >= size then
          emit()
        end
      end
    end

    local function onError(message)
      emit()
      done()
      observer:onError(message)
    end

    local function onCompleted()
      emit()
      done()
      observer:onCompleted()
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:catch(handler) -> cp.rx.Observable
--- Method
--- Returns an Observable that intercepts any errors from the previous and replace them with values produced by a new Observable.
---
--- Parameters:
---  * handler - An `Observable` or a `function` that returns an `Observable` to replace the source `Observable` in the event of an error.
---
--- Returns:
---  * The new `Observable`.
function Observable:catch(handler)
  handler = handler and (type(handler) == 'function' and handler or util.constant(handler))

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        observer:onNext(...)
      end
    end

    local function onError(e)
      if not active then
        return
      end

      if not handler then
        done()
        observer:onCompleted()
      end

      local success, continue = pcall(handler, e)
      if success and continue then
        if ref then ref:cancel() end
        ref = continue:subscribe(observer)
      else
        done()
        observer:onError(success and e or continue)
      end
    end

    local function onCompleted()
      done()
      observer:onCompleted()
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:combineLatest(...) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that runs a combinator function on the most recent values from a set of `Observables` whenever any of them produce a new value. The results of the combinator `function` are produced by the new `Observable`.
---
--- Parameters:
---  * ... - One or more `Observables` to combine. A combinator is a `function` that combines the latest result from each `Observable` and returns a single value.
---
--- Returns:
---  * The new `Observable`.
function Observable:combineLatest(...)
  local sources = {...}
  local combinator = remove(sources)
  if type(combinator) ~= 'function' then
    insert(sources, combinator)
    combinator = function(...) return ... end
  end
  insert(sources, 1, self)

  return Observable.create(function(observer)
    local latest = {}
    local pending = {util.unpack(sources)}
    local completed = {}
    local reference = {}

    local function onNext(i)
      return function(value)
        latest[i] = value
        pending[i] = nil

        if not next(pending) then
          util.tryWithObserver(observer, function()
            observer:onNext(combinator(util.unpack(latest)))
          end)
        end
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted(i)
      return function()
        insert(completed, i)

        if #completed == #sources then
          observer:onCompleted()
        end
      end
    end

    for i = 1, #sources do
      reference[i] = sources[i]:subscribe(onNext(i), onError, onCompleted(i))
    end

    return Reference.create(function ()
      for i = 1, #reference do
        if reference[i] then reference[i]:cancel() end
      end
    end)
  end)
end

--- cp.rx.Observable:compact() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the values of the first with falsy values removed.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:compact()
  return self:filter(util.identity)
end

--- cp.rx.Observable:concat(...) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the values produced by all the specified `Observables` in the order they are specified.
---
--- Parameters:
---  * ...     - The list of `Observables` to concatenate.
---
--- Returns:
---  * The new `Observable`.
function Observable:concat(other, ...)
  if not other then return self end

  local others = {...}

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      others = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        return observer:onNext(...)
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function chain()
      if active then
        ref = other:concat(util.unpack(others)):subscribe(onNext, onError, onCompleted)
        others = nil
      end
    end

    ref = self:subscribe(onNext, onError, chain)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:contains(value) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces a single `boolean` value representing whether or not the specified value was produced by the original.
---
--- Parameters:
---  * value - The value to search for. `==` is used for equality testing.
---
--- Returns:
---  * The new `Observable`.
function Observable:contains(value)
  return Observable.create(function(observer)
    local active, reference = true, nil

    local function done()
      active = false
      if reference then
        reference:cancel()
        reference = nil
      end
    end

    local function onNext(...)
      if active then
        local args = util.pack(...)

        if #args == 0 and value == nil then
          done()
          observer:onNext(true)
          observer:onCompleted()
        end

        for i = 1, #args do
          if args[i] == value then
            done()
            observer:onNext(true)
            observer:onCompleted()
          end
        end
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onNext(false)
        return observer:onCompleted()
      end
    end

    reference = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:count([predicate]) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that produces a single value representing the number of values produced by the source value that satisfy an optional predicate.
---
--- Parameters:
---  * predicate   - The predicate `function` used to match values.
---
--- Returns:
---  * The new `Observable`.
function Observable:count(predicate)
  predicate = predicate or util.constant(true)

  return Observable.create(function(observer)
    local active, ref = true, nil
    local count = 0

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        local success = util.tryWithObserver(observer, function(...)
          if predicate(...) then
            count = count + 1
          end
        end, ...)
        if not success then
          done()
        end
      end
    end

    local function onError(e)
      done()
      observer:onError(e)
    end

    local function onCompleted()
      done()
      observer:onNext(count)
      observer:onCompleted()
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:debounce(time[, scheduler]) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that mirrors the source `Observable`, except that it drops items emitted by the source that are followed by newer items before a timeout value expires on a specified [Scheduler](cp.rx.Scheduler.md). The timer resets on each emission.
---
--- Parameters:
---  * time        - The number of milliseconds.
---  * scheduler   - The scheduler. If not specified, it will use the [defaultScheduler](cp.rx.util#defaultScheduler].
---
--- Returns:
---  * The new `Observable`.
function Observable:debounce(time, scheduler)
  time = time or 0
  scheduler = scheduler or util.defaultScheduler()

  return Observable.create(function(observer)
    local debounced = {}

    local function wrap(key)
      return function(...)
        if debounced[key] then
          debounced[key]:cancel()
        end

        local values = util.pack(...)

        debounced[key] = scheduler:schedule(function()
          return observer[key](observer, util.unpack(values))
        end, time)
      end
    end

    local reference = self:subscribe(wrap('onNext'), wrap('onError'), wrap('onCompleted'))

    return Reference.create(function()
      if reference then reference:cancel() end
      for _, timeout in pairs(debounced) do
        timeout:cancel()
      end
    end)
  end)
end

--- cp.rx.Observable:defaultIfEmpty(...)
--- Method
--- Returns a new `Observable` that produces a default set of items if the source `Observable` produces no values.
---
--- Parameters:
---  * ... - Zero or more values to produce if the source completes without emitting anything.
---
--- Returns:
---  * The new `Observable`.
function Observable:defaultIfEmpty(...)
  local defaults = util.pack(...)

  return Observable.create(function(observer)
    local active, ref = true, nil
    local hasValue = false

    local function done()
      active = false
      defaults = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        hasValue = true
        observer:onNext(...)
      end
    end

    local function onError(e)
      done()
      observer:onError(e)
    end

    local function onCompleted()
      if active then
        active = false
        if not hasValue then
          observer:onNext(util.unpack(defaults))
        end
        done()
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:delay(time, scheduler) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the values of the original delayed by a time period.
---
--- Parameters:
---  * time - An amount in milliseconds to delay by, or a `function` which returns this value.
---  * scheduler - The [Scheduler](cp.rx.Scheduler.md) to run the `Observable` on. If not specified, it will use the [defaultScheduler](cp.rx.util#defaultScheduler].
---
--- Returns:
---  * The new `Observable`.
function Observable:delay(time, scheduler)
  time = type(time) ~= 'function' and util.constant(time) or time
  scheduler = scheduler or util.defaultScheduler()

  return Observable.create(function(observer)
    local actions = {}

    local function delay(key)
      return function(...)
        local arg = util.pack(...)
        local handle = scheduler:schedule(function()
          observer[key](observer, util.unpack(arg))
        end, time())
        insert(actions, handle)
      end
    end

    local reference = self:subscribe(delay('onNext'), delay('onError'), delay('onCompleted'))

    return Reference.create(function()
      if reference then reference:cancel() end
      for i = 1, #actions do
        actions[i]:cancel()
      end
      actions = nil
    end)
  end)
end

--- cp.rx.Observable:distinct() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the values from the original with duplicates removed.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:distinct()
  return Observable.create(function(observer)
    local values = {}

    local function onNext(x)
      if not values[x] then
        observer:onNext(x)
      end

      values[x] = true
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- cp.rx.Observable:distinctUntilChanged([comparator]) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that only produces values from the original if they are different from the previous value.
---
--- Parameters:
---  * comparator - A `function` used to compare 2 values. If unspecified, `==` is used.
---
--- Returns:
---  * The new `Observable`
function Observable:distinctUntilChanged(comparator)
  comparator = comparator or util.eq

  return Observable.create(function(observer)
    local first = true
    local currentValue = nil

    local function onNext(value, ...)
      local values = util.pack(...)
      util.tryWithObserver(observer, function()
        if first or not comparator(value, currentValue) then
          observer:onNext(value, util.unpack(values))
          currentValue = value
          first = false
        end
      end)
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- cp.rx.Observable:elementAt(index) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that produces the `n`th element produced by the source `Observable`.
---
--- Parameters:
---  * index - The index of the item, with an index of `1` representing the first.
---
--- Returns:
---  * The new `Observable`.
function Observable:elementAt(index)
  return Observable.create(function(observer)
    local reference
    local i = 1

    local function onNext(...)
      if i == index then
        observer:onNext(...)
        observer:onCompleted()
        if reference then
          reference:cancel()
        end
      else
        i = i + 1
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    reference = self:subscribe(onNext, onError, onCompleted)
    return reference
  end)
end

--- cp.rx.Observable:filter(predicate) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that only produces values of the first that satisfy a predicate.
---
--- Parameters:
---  * predicate - The predicate `function` used to filter values.
---
--- Returns:
---  * The new `Observable`.
function Observable:filter(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      predicate = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        local success = util.tryWithObserver(observer, function(...)
          if predicate(...) then
            return observer:onNext(...)
          end
        end, ...)
        if not success then
          done()
        end
      end
    end

    local function onError(e)
      if active then
        done()
        return observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        return observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:switchIfEmpty(alternate) -> cp.rx.Observable
--- Method
--- Switch to an alternate `Observable` if this one sends an `onCompleted` without any `onNext`s.
---
--- Parameters:
---  * alternate - An `Observable` to switch to if this does not send any `onNext` values before the `onCompleted`.
---
--- Returns:
---  * The new `Observable`.
function Observable:switchIfEmpty(alternate)
  return Observable.create(function(observer)
    local active, ref = true, nil
    local hasNext = false

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onCompleted()
      if active then
        if hasNext then
          done()
          observer:onCompleted()
        else
          active = false
          ref = alternate:subscribe(observer)
        end
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onNext(...)
      if active then
        hasNext = true
        observer:onNext(...)
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:finalize(handler) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that mirrors the source `Observable`, but will call a specified `function` when the source terminates on complete or error.
---
--- Parameters:
---  * handler - The handler `function` to call when `onError`/`onCompleted` occurs.
---
--- Returns:
---  * The new `Observable`.
function Observable:finalize(handler)
  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        observer:onNext(...)
      end
    end

    local function onError(message)
      if active then
        done()
        local ok = util.tryWithObserver(observer, handler)
        if ok then
          observer:onError(message)
        end
      end
    end

    local function onCompleted()
      if active then
        done()
        local ok = util.tryWithObserver(observer, handler)
        if ok then
          observer:onCompleted()
        end
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:find(predicate) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the first value of the original that satisfies a predicate.
---
--- Parameters:
---  * predicate - The predicate `function` used to find a value.
---
--- Returns:
---  * The new `Observable`.
function Observable:find(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function onNext(...)
      if active then
        local ok = util.tryWithObserver(observer, function(...)
          if predicate(...) then
            observer:onNext(...)
            onCompleted()
          end
        end, ...)
        if not ok then
          done()
        end
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:first() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that only produces the first result of the original. If no values are produced, an error is thrown.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
---
--- Notes:
---  * This is similar to [#next], but will throw an error if no `onNext` signal is sent before `onCompleted`.
function Observable:first()
  return self:take(1)
end

--- cp.rx.Observable:next() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces at most the first result from the original and then completes. Will not send an error if zero values are sent.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
---
--- Notes:
---  * This is similar to [#first], but will not throw an error if no `onNext` signal is sent before `onCompleted`.
function Observable:next()
  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onNext(...)
      if active then
        done()
        observer:onNext(...)
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:flatMap(callback) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that transform the items emitted by an `Observable` into `Observables`, then flatten the emissions from those into a single `Observable`.
---
--- Parameters:
---  * callback - The `function` to transform values from the original `Observable`.
---
--- Returns:
---  * The new `Observable`.
function Observable:flatMap(callback)
  callback = callback or util.identity
  return self:map(callback):flatten()
end

--- cp.rx.Observable:flatMapLatest([callback]) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that uses a callback to create `Observables` from the values produced by the source, then produces values from the most recent of these `Observables`.
---
--- Parameters:
---  * callback - The function used to convert values to Observables. Defaults to the [identity](cp.rx.util#identity) function.
---
--- Returns:
---  * The new `Observable`.
function Observable:flatMapLatest(callback)
  callback = callback or util.identity
  return Observable.create(function(observer)
    local active, outerRef, innerRef = true, nil, nil

    local function cancelOuter()
      if outerRef then
        outerRef:cancel()
        outerRef = nil
      end
    end

    local function cancelInner()
      if innerRef then
        innerRef:cancel()
        innerRef = nil
      end
    end

    local function done()
      active = false
      cancelOuter()
      cancelInner()
    end

    local function onNext(...)
      if active then
        observer:onNext(...)
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        return observer:onCompleted()
      end
    end

    local function subscribeInner(...)
      cancelInner()

      local ok = util.tryWithObserver(observer, function(...)
        innerRef = callback(...):subscribe(onNext, onError)
      end, ...)
      if not ok then
        done()
      end
    end

    outerRef = self:subscribe(subscribeInner, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:flatten()
--- Method
--- Returns a new `Observable` that subscribes to the `Observables` produced by the original and produces their values.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:flatten()
  local stopped = false
  local outerCompleted = false
  local waiting = 0
  return Observable.create(function(observer)
    local function onError(message)
      stopped = true
      return observer:onError(message)
    end
    local function onNext(observable)
      if stopped then
        return
      end

      local ref
      local function cancelSub()
        if ref then
          ref:cancel()
          ref = nil
        end
      end

      local function innerOnNext(...)
        if stopped then
            cancelSub()
        else
            observer:onNext(...)
        end
      end

      local function innerOnError(message)
        cancelSub()
        if not stopped then
            stopped = true
            observer:onError(message)
        end
      end

      local function innerOnCompleted()
        cancelSub()
        if not stopped then
            waiting = waiting - 1
            if waiting == 0 and outerCompleted then
                stopped = true
                return observer:onCompleted()
            end
        end
      end

      waiting = waiting + 1
      ref = observable:subscribe(innerOnNext, innerOnError, innerOnCompleted)
    end

    local function onCompleted()
      if not stopped then
        outerCompleted = true
        if waiting == 0 then
            stopped = true
            return observer:onCompleted()
        end
      end
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- cp.rx.Observable:ignoreElements() -> cp.rx.Observable
--- Method
--- Returns an `Observable` that terminates when the source terminates but does not produce any elements.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:ignoreElements()
  return Observable.create(function(observer)
    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(nil, onError, onCompleted)
  end)
end

--- cp.rx.Observable:last() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that only produces the last result of the original.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:last()
  return Observable.create(function(observer)
    local value
    local empty = true

    local function onNext(...)
      value = {...}
      empty = false
    end

    local function onError(e)
      observer:onError(e)
    end

    local function onCompleted()
      if not empty then
        observer:onNext(util.unpack(value or {}))
      end

      observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- cp.rx.Observable:map(callback) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the values of the original transformed by a `function`.
---
--- Parameters:
---  * callback - The `function` to transform values from the original `Observable`.
---
--- Returns:
---  * The new `Observable`.
function Observable:map(callback)
  return Observable.create(function(observer)
    callback = callback or util.identity
    local active, ref = true, nil
    local function done()
      active = false
      callback = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        local success = util.tryWithObserver(observer, function(...)
          return observer:onNext(callback(...))
        end, ...)
        if not success then
          done()
        end
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:max() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the maximum value produced by the original.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:max()
  return self:reduce(math.max)
end

--- cp.rx.Observable:merge(...) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the values produced by all the specified `Observables` in the order they are produced.
---
--- Parameters:
---  * ... - One or more `Observables` to merge.
---
--- Returns:
---  * The new `Observable`.
function Observable:merge(...)
  return Observable.of(self, ...):flatten()
end

--- cp.rx.Observable:min() -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the minimum value produced by the original.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:min()
  return self:reduce(math.min)
end

--- cp.rx.Observable:partition(predicate) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that produces the values of the original inside tables.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:pack()
  return self:map(util.pack)
end

--- cp.rx.Observable:partition(predicate) -> cp.rx.Observable, cp.rx.Observable
--- Method
--- Returns two `Observables`: one that produces values for which the predicate returns truthy for, and another that produces values for which the predicate returns falsy.
---
--- Parameters:
---  * predicate - The predicate `function` used to partition the values.
---
--- Returns:
---  * The 'truthy' `Observable`.
---  * The 'falsy' `Observable`.
function Observable:partition(predicate)
  return self:filter(predicate), self:reject(predicate)
end

--- cp.rx.Observable:pluck(...) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces values computed by extracting the given keys from the tables produced by the original.
---
--- Parameters:
---  * ... - The key to extract from the `table`. Multiple keys can be specified to recursively pluck values from nested tables.
---
--- Returns:
---  * The new `Observable`.
function Observable:pluck(key, ...)
  if not key then return self end

  if type(key) ~= 'string' and type(key) ~= 'number' then
    return Observable.throw('pluck key must be a string')
  end

  return Observable.create(function(observer)
    local function onNext(t)
      return observer:onNext(t[key])
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end):pluck(...)
end

--- cp.rx.Observable:reduce(accumulator[, seed]) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces a single value computed by accumulating the results of running a `function` on each value produced by the original `Observable`.
---
--- Parameters:
---  * accumulator - Accumulates the values of the original `Observable`. Will be passed the return value of the last call as the first argument and the current values as the rest of the arguments.
---  * seed - An optional value to pass to the accumulator the first time it is run.
---
--- Returns:
---  * The new `Observable`.
function Observable:reduce(accumulator, seed)
  return Observable.create(function(observer)
    local active, ref = true, nil
    local result = seed
    local first = true

    local function done()
      active = false
      result = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        if first and seed == nil then
          result = ...
          first = false
        else
          local ok = util.tryWithObserver(observer, function(...)
            result = accumulator(result, ...)
          end, ...)
          if not ok then
            done()
          end
        end
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        local final = result
        done()
        observer:onNext(final)
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:reject(predicate) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces values from the original which do not satisfy a predicate.
---
--- Parameters:
---  * predicate - The predicate `function` used to reject values.
---
--- Returns:
---  * The new `Observable`.
function Observable:reject(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      predicate = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        local success = util.tryWithObserver(observer, function(...)
          if not predicate(...) then
            return observer:onNext(...)
          end
        end, ...)
        if not success then
          done()
        end
      end
    end

    local function onError(e)
      if active then
        done()
        return observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        return observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)end

--- cp.rx.Observable:retry([count]) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that restarts in the event of an error.
---
--- Parameters:
---  * count - The maximum number of times to retry. If left unspecified, an infinite number of retries will be attempted.
---
--- Returns:
---  * The new `Observable`.
function Observable:retry(count)
  return Observable.create(function(observer)
    local active, ref = true, nil
    local retries = 0

    local function cancelRef()
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function done()
      active = false
      cancelRef()
    end

    local function onNext(...)
      if active then
        return observer:onNext(...)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function onError(message)
      if active then
        cancelRef()
        retries = retries + 1
        if count and retries == count then
          active = false
          observer:onError(message)
        else
          ref = self:subscribe(onNext, onError, onCompleted)
        end
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:retryWithDelay(count[, delay[, scheduler]]) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that restarts in the event of an error.
---
--- Parameters:
---  * count - The maximum number of times to retry.  If left unspecified, an infinite number of retries will be attempted.
---  * delay - The `function` returning or a `number` representing the delay in milliseconds or a `function`. If left unspecified, defaults to 1000 ms (1 second).
---  * scheduler - The [Scheduler](cp.rx.Scheduler.md) to use. If not specified, it will use the [defaultScheduler](cp.rx.util#defaultScheduler].
---
--- Returns:
---  * The new `Observable`.
function Observable:retryWithDelay(count, delay, scheduler)
  delay = type(delay) == "function" and delay or util.constant(delay or 1000)
  return Observable.create(function(observer)
    local active, ref = true, nil
    local retries = 0

    local function cancelRef()
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function done()
      active = false
      cancelRef()
    end

    local function onNext(...)
      if active then
        observer:onNext(...)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function onError(message)
      if active then
        cancelRef()
        retries = retries + 1
        if count and retries == count then
          done()
          observer:onError(message)
        else
          scheduler = scheduler or util.defaultScheduler()
          ref = scheduler:schedule(function()
            ref = self:subscribe(onNext, onError, onCompleted)
          end, delay())
        end
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:sample(sampler) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces its most recent value every time the specified observable produces a value.
---
--- Parameters:
---  * sampler - The `Observable` that is used to sample values from this `Observable`.
---
--- Returns:
---  * The new `Observable`.
function Observable:sample(sampler)
  if not Observable.is(sampler) then error('Expected an Observable') end

  return Observable.create(function(observer)
    local active, sourceRef, sampleRef = true, nil, nil
    local latest = {}

    local function cancelSource()
      if sourceRef then
        sourceRef:cancel()
        sourceRef = nil
      end
    end

    local function done()
      active = false
      cancelSource()
      if sampleRef then
        sampleRef:cancel()
        sampleRef = nil
      end
    end

    local function setLatest(...)
      if active then
        latest = util.pack(...)
      end
    end

    local function onNext()
      if active and #latest > 0 then
        observer:onNext(util.unpack(latest))
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    sourceRef = self:subscribe(setLatest, onError, cancelSource)
    sampleRef = sampler:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:scan(accumulator, seed) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces values computed by accumulating the results of running a `function` on each value produced by the original `Observable`.
---
--- Parameters:
---  * accumulator - Accumulates the values of the original `Observable`. Will be passed the return value of the last call as the first argument and the current values as the rest of the arguments. Each value returned from this `function` will be emitted by the `Observable`.
---  * seed - A value to pass to the accumulator the first time it is run.
---
--- Returns:
---  * The new `Observable`.
function Observable:scan(accumulator, seed)
  return Observable.create(function(observer)
    local active, ref = true, nil
    local result = seed
    local first = true

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        if first and seed == nil then
          result = ...
          first = false
        else
          local ok = util.tryWithObserver(observer, function(...)
            result = accumulator(result, ...)
            observer:onNext(result)
          end, ...)
          if not ok then
            done()
          end
        end
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:skip([n]) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that skips over a specified number of values produced by the original and produces the rest.
---
--- Parameters:
---  * n - The number of values to ignore. Defaults to `1`.
---
--- Returns:
---  * The new `Observable`
function Observable:skip(n)
  n = n or 1

  return Observable.create(function(observer)
    local i = 1

    local function onNext(...)
      if i > n then
        observer:onNext(...)
      else
        i = i + 1
      end
    end

    local function onError(e)
      observer:onError(e)
    end

    local function onCompleted()
      observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

local buffer = {}
buffer.__index = buffer

function buffer.new()
  return setmetatable({
    first = 1, last = 0
  }, buffer)
end

function buffer:size()
  return self.last - self.first + 1
end

function buffer:pop()
  if self:size() > 0 then
    local first = self.first
    local values = self[first]
    self[first] = nil
    self.first = first + 1
    return values
  end
end

function buffer:push(value)
  self.last = self.last + 1
  buffer[self.last] = value
end

--- cp.rx.Observable:skipLast(count) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that omits a specified number of values from the end of the original `Observable`.
---
--- Parameters:
---  * count - The number of items to omit from the end.
---
--- Returns:
---  * The new `Observable`.
function Observable:skipLast(count)
  return Observable.create(function(observer)
    -- cycling buffer
    local active, ref = true, nil
    local buff = buffer.new()

    local function done()
      active = false
      buff = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function emit()
      while buff:size() > count do
        observer:onNext(util.unpack(buff:pop()))
      end
    end

    local function onNext(...)
      if active then
        buff:push(util.pack(...))
        emit()
      end
    end

    local function onError(message)
      if active then
        done()
        return observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        return observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:skipUntil(other) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that skips over values produced by the original until the specified `Observable` produces a value.
---
--- Parameters:
---  * other - The `Observable` that triggers the production of values.
---
--- Returns:
---  * The new `Observable`.
function Observable:skipUntil(other)
  return Observable.create(function(observer)
    local active, ref, otherRef = true, nil, nil
    local triggered = false

    local function cancelOther()
      if otherRef then
        otherRef:cancel()
        otherRef = nil
      end
    end

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
      cancelOther()
    end

    local function trigger()
      triggered = true
      cancelOther()
    end

    local function onNext(...)
      if active and triggered then
        observer:onNext(...)
      end
    end

    local function onError()
      if active and triggered then
        done()
        observer:onError()
      end
    end

    local function onCompleted()
      if active and triggered then
        done()
        observer:onCompleted()
      end
    end

    otherRef = other:subscribe(trigger, trigger, trigger)
    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(done)
  end)
end

--- cp.rx.Observable:skipWhile(predicate) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that skips elements until the predicate returns `falsy` for one of them.
---
--- Parameters:
---  * predicate - The predicate `function` used to continue skipping values.
---
--- Returns:
---  * The new `Observable`.
function Observable:skipWhile(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local active, ref = true, nil
    local skipping = true

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        if skipping then
          local ok = util.tryWithObserver(observer, function(...)
            skipping = predicate(...)
          end, ...)
          if not ok then
            done()
            return
          end
        end

        if not skipping then
          observer:onNext(...)
        end
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:startWith(...) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces the specified values followed by all elements produced by the source `Observable`.
---
--- Parameters:
---  * values - The values to produce before the Observable begins producing values normally.
---
--- Returns:
---  * The new `Observable`.
function Observable:startWith(...)
  local values = util.pack(...)
  return Observable.create(function(observer)
    observer:onNext(util.unpack(values))
    return self:subscribe(observer)
  end)
end

--- cp.rx.Observable:sum() -> cp.rx.Observable
--- Method
--- Returns an `Observable` that produces a single value representing the sum of the values produced by the original.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:sum()
  return self:reduce(function(x, y) return x + y end, 0)
end

--- cp.rx.Observable:switch() -> cp.rx.Observable
--- Method
--- Given an `Observable` that produces `Observables`, returns an `Observable` that produces the values produced by the most recently produced `Observable`.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:switch()
  return Observable.create(function(observer)
    local active, ref, sourceRef = true, nil, nil

    local function cancelSource()
      if sourceRef then
        sourceRef:cancel()
        sourceRef = nil
      end
    end

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
      cancelSource()
    end

    local function onNext(...)
      if active then
        observer:onNext(...)
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function switch(source)
      if active then
        cancelSource()
        sourceRef = source:subscribe(onNext, onError, nil)
      end
    end

    ref = self:subscribe(switch, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:take([n]) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that only produces the first n results of the original.
---
--- Parameters:
---  * n - The number of elements to produce before completing. Defaults to `1`.
---
--- Returns:
---  * The new `Observable`.
function Observable:take(n)
  n = n or 1

  return Observable.create(function(observer)
    if n <= 0 then
      observer:onCompleted()
      return
    end

    local i = 1
    local done = false
    local ref

    local function onCompleted()
      if not done then
        done = true
        if ref then
          ref:cancel()
        end
        if i <= n then
          observer:onError(format("Expected at least %d, got %d.", n, i-1))
        else
          observer:onCompleted()
        end
      end
    end

    local function onNext(...)
      if not done and i <= n then
        i = i + 1
        observer:onNext(...)

        if i > n then
          onCompleted()
        end
      end
    end

    local function onError(e)
      if not done then
        done = true
        if ref then
          ref:cancel()
        end
        return observer:onError(e)
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)

    return Reference.create(function()
      done = true
      if ref then
        ref:cancel()
      end
    end)
  end)
end

--- cp.rx.Observable:takeLast(count) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that produces a specified number of elements from the end of a source `Observable`.
---
--- Parameters:
---  * count - The number of elements to produce.
---
--- Returns:
---  * The new `Observable`.
function Observable:takeLast(count)
  return Observable.create(function(observer)
    local active, ref = true, nil
    local buff = buffer.new()

    local function done()
      active = false
      buff = nil
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        buff:push(util.pack(...))
        if buff:size() > count then
          buff:pop()
        end
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        active = false
        while buff:size() > 0 do
          observer:onNext(util.unpack(buff:pop()))
        end
        done()
        observer:onCompleted()
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:takeUntil(other) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that completes when the specified `Observable` fires.
---
--- Parameters:
---  * other - The `Observable` that triggers completion of the original.
---
--- Returns:
---  * The new `Observable`.
function Observable:takeUntil(other)
  return Observable.create(function(observer)
    local active, ref, otherRef = true, nil, nil
    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
      if otherRef then
        otherRef:cancel()
        otherRef = nil
      end
    end

    local function onNext(...)
      if active then
        observer:onNext(...)
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    otherRef = other:subscribe(onCompleted, onCompleted, onCompleted)
    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:takeWhile(predicate) -> cp.rx.Observable
--- Method
--- Returns a new `Observable` that produces elements until the predicate returns `falsy`.
---
--- Parameters:
---  * predicate - The predicate `function` used to continue production of values.
---
--- Returns:
---  * The new `Observable`.
function Observable:takeWhile(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local active, ref = true, nil
    local taking = true

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active and taking then
        local ok = util.tryWithObserver(observer, function(...)
          taking = predicate(...)
        end, ...)

        if not ok then
          done()
        else
          if taking then
            observer:onNext(...)
          else
            done()
            observer:onCompleted()
          end
        end
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    ref =  self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:tap(onNext[, onError[, onCompleted]]) -> cp.rx.Observable
--- Method
--- Runs a `function` each time this `Observable` has activity. Similar to [subscribe](#subscribe) but does not create a subscription.
---
--- Parameters:
---  * onNext - Run when the `Observable` produces values.
---  * onError - Run when the `Observable` encounters a problem.
---  * onCompleted - Run when the `Observable` completes.
---
--- Returns:
---  * The new `Observable`.
function Observable:tap(_onNext, _onError, _onCompleted)
  _onNext = _onNext or util.noop
  _onError = _onError or util.noop
  _onCompleted = _onCompleted or util.noop

  return Observable.create(function(observer)
    local active, ref = true, nil

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function onNext(...)
      if active then
        local ok = util.tryWithObserver(observer, function(...)
          _onNext(...)
        end, ...)

        if ok then
          observer:onNext(...)
        else
          done()
        end
      end
    end

    local function onError(message)
      if active then
        done()
        local ok = util.tryWithObserver(observer, function()
          _onError(message)
        end)
        if ok then
          observer:onError(message)
        end
      end
    end

    local function onCompleted()
      if active then
        done()
        local ok = util.tryWithObserver(observer, function()
          _onCompleted()
        end)
        if ok then
          observer:onCompleted()
        end
      end
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:timeout(timeInMs, next[, scheduler]) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that will emit an error if the specified time is exceded since the most recent `next` value.
---
--- Parameters:
---  * timeInMs - The time in milliseconds to wait before an error is emitted.
---  * next - If a `string`, it will be sent as an error. If an `Observable`, switch to that `Observable` instead of sending an error.
---  * scheduler - The scheduler to use. If not specified, it will use the [defaultScheduler](cp.rx.util#defaultScheduler].
---
--- Returns:
---  * The new `Observable`.
function Observable:timeout(timeInMs, next, scheduler)
  timeInMs = type(timeInMs) == "function" and timeInMs or util.constant(timeInMs)
  scheduler = scheduler or util.defaultScheduler()

  return Observable.create(function(observer)
    local active, ref, actionRef = true, nil, nil

    local function cancelRef()
      if ref then
        ref:cancel()
        ref = nil
      end
    end

    local function done()
      active = false
      cancelRef()
      if actionRef then
          actionRef:cancel()
          actionRef = nil
      end
    end

    local function timedOut()
      if active then
        if Observable.is(next) then
          cancelRef()
          ref = next:subscribe(
            function(...)
              if active then
                observer:onNext(...)
              end
            end,
            function(e)
              if active then
                done()
                observer:onError(e)
              end
            end,
            function()
              if active then
                done()
                observer:onCompleted()
              end
            end
          )
        else
          done()
          observer:onError(next or format("Timed out after %d ms.", timeInMs()))
        end
      end
    end

    local function onNext(...)
      if active then
        -- restart the timer...
        if actionRef then
          actionRef:cancel()
          actionRef = scheduler:schedule(timedOut, timeInMs())
          observer:onNext(...)
        end
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    actionRef = scheduler:schedule(timedOut, timeInMs())
    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable:unpack() -> cp.rx.Observable
--- Method
--- Returns an `Observable` that unpacks the `tables` produced by the original.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:unpack()
  return self:map(util.unpack)
end

--- cp.rx.Observable:unwrap() -> cp.rx.Observable
--- Method
--- Returns an `Observable` that takes any values produced by the original that consist of multiple return values and produces each value individually.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new `Observable`.
function Observable:unwrap()
  return Observable.create(function(observer)
    local function onNext(...)
      local values = {...}
      for i = 1, #values do
        observer:onNext(values[i])
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- cp.rx.Observable:with(...) -> cp.rx.Observable
--- Method
--- Returns an `Observable` that produces values from the original along with the most recently produced value from all other specified `Observables`. Note that only the first argument from each source `Observable` is used.
---
--- Parameters:
---  * ... - The `Observables` to include the most recent values from.
---
--- Returns:
---  * The new `Observable`.
function Observable:with(...)
  local sources = {...}

  return Observable.create(function(observer)
    local active, ref = true, nil
    local latest = List.sized(#sources)
    local sourceRefs = List.sized(#sources)

    local function done()
      active = false
      if ref then
        ref:cancel()
        ref = nil
      end
      local count = #sourceRefs
      for i = 1,count do
        latest[i] = nil
        local sourceRef = sourceRefs[i]
        if sourceRef then
          sourceRefs[i]:cancel()
          sourceRefs[i] = nil
        end
      end
        latest = nil
      sourceRefs = nil
    end

    local function setLatest(i)
      return function(value)
        latest[i] = value
      end
    end

    local function onNext(value)
      if active then
        observer:onNext(value, util.unpack(latest))
      end
    end

    local function onError(e)
      if active then
        done()
        observer:onError(e)
      end
    end

    local function onCompleted()
      if active then
        done()
        observer:onCompleted()
      end
    end

    local function cancelSource(i)
      return function()
        local sourceRef = sourceRefs[i]
        if sourceRef then
          sourceRef:cancel()
          sourceRefs[i] = nil
        end
      end
    end

    for i = 1, #sources do
      sourceRefs[i] = sources[i]:subscribe(setLatest(i), cancelSource(i), cancelSource(i))
    end

    ref = self:subscribe(onNext, onError, onCompleted)
    return Reference.create(done)
  end)
end

--- cp.rx.Observable.zip(...) -> cp.rx.Observable
--- Constructor
--- Returns an `Observable` that merges the values produced by the source `Observables` by grouping them by their index.  The first `onNext` event contains the first value of all of the sources, the second `onNext` event contains the second value of all of the sources, and so on.  `onNext` is called a number of times equal to the number of values produced by the `Observable` that produces the fewest number of values.
---
--- Parameters:
---  * ...       - The `Observables` to zip.
---
--- Returns:
---  * The new `Observable`.
function Observable.zip(...)
  local sources = util.pack(...)
  local count = #sources

  return Observable.create(function(observer)
    local active = true
    local refs = List.sized(count)
    local values = List.sized(count)
    for i = 1, count do
      values[i] = Queue()
    end

    local function done()
      active = false
      if values ~= nil then
        values:size(0)
        values = nil
      end
      if refs ~= nil then
        for i = 1, count do
          local ref = refs[i]
          if ref then
            ref:cancel()
            refs[i] = nil
          end
        end
        refs = nil
      end
    end

    local function isReady()
      for i = 1,count do
        if #values[i] == 0 then
          return false
        end
      end
      return true
    end

    local function onNext(i)
      return function(...)
        if active then
          values[i]:pushRight(util.pack(...))

          if isReady() then
            local payload = {}

            for j = 1, count do
              local args = values[j]:popLeft()
              for _,arg in ipairs(args) do
                  insert(payload, arg)
              end
            end

            observer:onNext(util.unpack(payload))
          end
        end
      end
    end

    local function onError(message)
      if active then
        done()
        observer:onError(message)
      end
    end

    local function onCompleted(i)
      return function()
        if active then
          if refs and refs[i] then
            refs[i] = nil
            refs:trim()
          end
          if refs == nil or #refs:trim() == 0 or #values[i] == 0 then
            done()
            observer:onCompleted()
          end
        end
      end
    end

    for i = 1, count do
      -- have to check if `refs` is still a thing each time
      -- since it's possible that a source may close it immediately.
      local ref = sources[i]:subscribe(onNext(i), onError, onCompleted(i))
      if refs then
        refs[i] = ref
      else
        break
      end
    end
    return Reference.create(done)
  end)
end

Observable.wrap = Observable.buffer
Observable['repeat'] = Observable.replicate

return Observable