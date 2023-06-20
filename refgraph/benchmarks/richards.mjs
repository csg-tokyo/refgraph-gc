// This benchmark is derived from richards.rb and richards.js
// in Stefan Marr's "Are We Fast Yet?" benchmark.
//   https://github.com/smarr/are-we-fast-yet
//
// Only the instances of Scheduler and Packets are allocated in JavaScript
// while the other instances are in Ruby.

// The benchmark in its current state is a derivation from the SOM version,
// which is derived from Mario Wolczko's Smalltalk version of DeltaBlue.
//
// The original license details are availble here:
// http://web.archive.org/web/20050825101121/http://www.sunlabs.com/people/mario/java_benchmarking/index.html
'use strict';

var rubyFactory;

export function setFactory(factory) {
  rubyFactory = factory
}

export async function benchmark(innerIterations) {
  for (var i = 0; i < innerIterations; i++)
    if (!await new Richards().benchmark())
      return i;

  return true;
}

var NO_TASK = null,
  NO_WORK   = null,
  IDLER     = 0,
  WORKER    = 1,
  HANDLER_A = 2,
  HANDLER_B = 3,
  DEVICE_A  = 4,
  DEVICE_B  = 5,
  NUM_TYPES = 6,

  DEVICE_PACKET_KIND = 0,
  WORK_PACKET_KIND   = 1,

  DATA_SIZE = 4,

  TRACING = false;

function Richards() {
}

Richards.prototype.benchmark = async function () {
  return (new Scheduler()).start();
};

Richards.prototype.verifyResult = function (result) {
  return result;
};

function RBObject() {}

RBObject.prototype.append = function (packet, queueHead) {
  packet.link = NO_WORK;
  if (NO_WORK === queueHead) {
    return packet;
  }

  var mouse = queueHead,
    link;

  while (NO_WORK !== (link = mouse.link)) {
    mouse = link;
  }
  mouse.link = packet;
  return queueHead;
};

function Scheduler() {
  RBObject.call(this);

  // init tracing
  this.layout = 0;

  // init scheduler
  this.queuePacketCount = 0;
  this.holdCount = 0;
  this.taskTable = new Array(NUM_TYPES).fill(NO_TASK);
  this.taskList  = NO_TASK;

  this.currentTask = null;
  this.currentTaskIdentity = 0;
}
Scheduler.prototype = Object.create(RBObject.prototype);

Scheduler.prototype.createDevice = async function (identity, priority, workPacket,
                                                   state) {
  var data = await rubyFactory.DeviceTaskDataRecord(),
    that = this;

  await this.createTask(identity, priority, workPacket, state, data,
    async function(workArg, wordArg) {
      var dataRecord = wordArg,
        functionWork = workArg;
      if (NO_WORK === functionWork) {
        if (NO_WORK === (functionWork = await dataRecord.pending())) {
          return await that.markWaiting();
        } else {
          await dataRecord.setPending(NO_WORK);
          return await that.queuePacket(functionWork);
        }
      } else {
        await dataRecord.setPending(functionWork);
        if (TRACING) {
          that.trace(functionWork.datum);
        }
        return that.holdSelf();
      }
    });
};

Scheduler.prototype.createHandler = async function (identity, priority, workPacket,
                                              state) {
  var data = await rubyFactory.HandlerTaskDataRecord(),
    that = this;
  await this.createTask(identity, priority, workPacket, state, data,
    async function (work, word) {
      var dataRecord = word;
      if (NO_WORK !== work) {
        if (WORK_PACKET_KIND === work.kind) {
          await dataRecord.work_in_add(work);
        } else {
          await dataRecord.device_in_add(work);
        }
      }

      var workPacket;
      if (NO_WORK === (workPacket = await dataRecord.work_in())) {
        return await that.markWaiting();
      } else {
        var count = workPacket.datum;
        if (count >= DATA_SIZE) {
          await dataRecord.set_work_in(workPacket.link);
          return await that.queuePacket(workPacket);
        } else {
          var devicePacket;
          if (NO_WORK === (devicePacket = await dataRecord.device_in())) {
            return await that.markWaiting();
          } else {
            dataRecord.set_device_in(devicePacket.link);
            devicePacket.datum  = workPacket.data[count];
            workPacket.datum    = count + 1;
            return await that.queuePacket(devicePacket);
          }
        }
      }
    });
};

Scheduler.prototype.createIdler = async function (identity, priority, work, state) {
  var data = await rubyFactory.IdleTaskDataRecord(),
    that = this;
  await this.createTask(identity, priority, work, state, data,
    async function (workArg, wordArg) {
      var dataRecord = wordArg;
      await dataRecord.addToCount(-1);
      if (0 === await dataRecord.count()) {
        return await that.holdSelf();
      } else {
        if (0 === (await dataRecord.control() & 1)) {
          await dataRecord.divControlBy(2);
          return await that.release(DEVICE_A);
        } else {
          await dataRecord.setControl((await dataRecord.control() / 2) ^ 53256);
          return await that.release(DEVICE_B);
        }
      }
    });
};

Scheduler.prototype.createPacket = async function (link, identity, kind) {
  return new Packet(link, identity, kind);
};

Scheduler.prototype.createTask = async function (identity, priority, work, state,
                                                 data, fn) {
  var t = await rubyFactory.TaskControlBlock(this.taskList, identity, priority, work, state,
                                             data, fn);
  this.taskList = t;
  this.taskTable[identity] = t;
};

Scheduler.prototype.createWorker = async function (identity, priority, workPacket, state) {
  var dataRecord = await rubyFactory.WorkerTaskDataRecord(),
    that = this;
  await this.createTask(identity, priority, workPacket, state, dataRecord,
    async function (work, word) {
      var data = word;
      if (NO_WORK === work) {
        return await that.markWaiting();
      } else {
        await data.setDestination((HANDLER_A === await data.destination()) ? HANDLER_B : HANDLER_A);
        work.identity = await data.destination();
        work.datum = 0;
        for (var i = 0; i < DATA_SIZE; i++) {
          var count = await data.count();
          count += 1;
          if (count > 26) { count = 1; }
          data.setCount(count);
          work.data[i] = 65 + count - 1;
        }
        return await that.queuePacket(work);
      }
    });
};

Scheduler.prototype.start = async function () {
  var workQ;

  var rubyTaskState = await Ruby.exec('TaskState')
  await this.createIdler(IDLER, 0, NO_WORK, await rubyTaskState.running());
  workQ = await this.createPacket(NO_WORK, WORKER, WORK_PACKET_KIND);
  workQ = await this.createPacket(workQ,   WORKER, WORK_PACKET_KIND);

  await this.createWorker(WORKER, 1000, workQ, await rubyTaskState.waiting_with_packet());
  workQ = await this.createPacket(NO_WORK, DEVICE_A, DEVICE_PACKET_KIND);
  workQ = await this.createPacket(workQ,   DEVICE_A, DEVICE_PACKET_KIND);
  workQ = await this.createPacket(workQ,   DEVICE_A, DEVICE_PACKET_KIND);

  await this.createHandler(HANDLER_A, 2000, workQ, await rubyTaskState.waiting_with_packet());
  workQ = await this.createPacket(NO_WORK, DEVICE_B, DEVICE_PACKET_KIND);
  workQ = await this.createPacket(workQ,   DEVICE_B, DEVICE_PACKET_KIND);
  workQ = await this.createPacket(workQ,   DEVICE_B, DEVICE_PACKET_KIND);

  await this.createHandler(HANDLER_B, 3000,   workQ, await rubyTaskState.waiting_with_packet());
  await this.createDevice(DEVICE_A,   4000, NO_WORK, await rubyTaskState.waiting());
  await this.createDevice(DEVICE_B,   5000, NO_WORK, await rubyTaskState.waiting());

  await this.schedule();

  return this.queuePacketCount == 23246 && this.holdCount == 9297;
};

Scheduler.prototype.findTask = function (identity) {
  var t = this.taskTable[identity];
  if (NO_TASK == t) { throw "findTask failed"; }
  return t;
};

Scheduler.prototype.holdSelf = async function () {
  this.holdCount += 1;
  await this.currentTask.set_task_holding(true);
  return await this.currentTask.link();
};

Scheduler.prototype.queuePacket = async function (packet) {
  var t = this.findTask(packet.identity);
  if (NO_TASK == t) { return NO_TASK; }

  this.queuePacketCount += 1;

  packet.link = NO_WORK;
  packet.identity = this.currentTaskIdentity;
  return await t.add_input_and_check_priority(packet, this.currentTask);
};

Scheduler.prototype.release = async function (identity) {
  var t = this.findTask(identity);
  if (NO_TASK == t) { return NO_TASK; }
  await t.set_task_holding(false);
  if (await t.priority() > await this.currentTask.priority()) {
    return t;
  } else {
    return this.currentTask;
  }
};

Scheduler.prototype.trace = function (id) {
  this.layout -= 1;
  if (0 >= this.layout) {
    process.stdout.write("\n");
    this.layout = 50;
  }
  process.stdout.write(id);
};

Scheduler.prototype.markWaiting = async function () {
  await this.currentTask.set_task_waiting(true);
  return this.currentTask;
};

Scheduler.prototype.schedule = async function () {
  this.currentTask = this.taskList;
  while (NO_TASK != this.currentTask) {
    if (await this.currentTask.is_task_holding_or_waiting()) {
      this.currentTask = await this.currentTask.link();
    } else {
      this.currentTaskIdentity = await this.currentTask.identity();
      if (TRACING) { this.trace(this.currentTaskIdentity); }
      this.currentTask = await this.currentTask.run_task();
    }
  }
};

function Packet(link, identity, kind) {
  RBObject.call(this);
  this.link     = link;
  this.identity = identity;
  this.kind     = kind;
  this.datum    = 0;
  this.data     = new Array(DATA_SIZE).fill(0);
}
Packet.prototype = Object.create(RBObject.prototype);
