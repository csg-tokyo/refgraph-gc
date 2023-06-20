// This benchmark is derived from cd.rb and cd.js
// in Stefan Marr's "Are We Fast Yet?" benchmark.
//   https://github.com/smarr/are-we-fast-yet
//
// Only the instances of CollisionDetector and Simulator are allocated
// in JavaScript while the other instances are in Ruby.

// Copyright (c) 2001-2010, Purdue University. All rights reserved.
// Copyright (C) 2015 Apple Inc. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//  * Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//  * Neither the name of the Purdue University nor the
//    names of its contributors may be used to endorse or promote products
//    derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"use strict";

import * as som from './som.mjs';

export async function benchmark(numAircrafts) {
  horizontal = await (await Ruby.exec('Vector2D')).new(GOOD_VOXEL_SIZE, 0);
  vertical = await (await Ruby.exec('Vector2D')).new(0, GOOD_VOXEL_SIZE);

  var numFrames = 200;
  var simulator = await new Simulator().init(numAircrafts);
  var detector = await new CollisionDetector().init();

  var actualCollisions = 0;
  for (var i = 0; i < numFrames; ++i) {
    var time = i / 10;

    var frame = await simulator.simulate(time);
    var collisions = await detector.handleNewFrame(frame);
    actualCollisions += collisions.size();
  }
  return actualCollisions;
}

function CollisionDetector() {}

CollisionDetector.prototype.init = async function () {
  this.state = await (await Ruby.exec('RedBlackTree')).new();
  return this;
}

CollisionDetector.prototype.handleNewFrame = async function (frame) {
  var motions = new som.Vector();
  var seen = await (await Ruby.exec('RedBlackTree')).new();
  var that = this;
  await frame.asyncForEach(async function (aircraft) {
    var oldPosition = await that.state.put(await aircraft.callsign(), await aircraft.position());
    var newPosition = await aircraft.position();
    await seen.put(await aircraft.callsign(), true);

    if (!oldPosition) {
      // Treat newly introduced aircraft as if they were stationary.
      oldPosition = newPosition;
    }
    var m = await (await Ruby.exec('Motion')).new(await aircraft.callsign(), oldPosition, newPosition)
    motions.append(m);
  });

  // Remove aircraft that are no longer present.
  var toRemove = new som.Vector();
  await this.state.apply(async function(e) {
    if (!(await seen.get(await e.key()))) {
      toRemove.append(e.key);
    }
  });

  await toRemove.asyncForEach(async function (e) { await that.state.remove(e); });

  var allReduced = await reduceCollisionSet(motions);
  var collisions = new som.Vector();

  await allReduced.asyncForEach(async function (reduced) {
    for (var i = 0; i < reduced.size(); ++i) {
      var motion1 = reduced.at(i);
      for (var j = i + 1; j < reduced.size(); ++j) {
        var motion2 = reduced.at(j);
        var collision = await motion1.find_intersection(motion2);
        if (collision) {
          collisions.append(
            await (await Ruby.exec('Collision')).new(
              await motion1.callsign(),
              await motion2.callsign(),
              collision
            )
          );
        }
      }
    }
  });

  return collisions;
};

var MIN_X = 0,
  MIN_Y = 0,
  MAX_X = 1000,
  MAX_Y = 1000,
  PROXIMITY_RADIUS = 1,
  GOOD_VOXEL_SIZE = PROXIMITY_RADIUS * 2;

var horizontal = null;
var vertical = null;

async function isInVoxel(voxel, motion) {
  if ((await voxel.x()) > MAX_X ||
    (await voxel.x()) < MIN_X ||
    (await voxel.y()) > MAX_Y ||
    (await voxel.y()) < MIN_Y) {
    return false;
  }

  var init = await motion.pos_one();
  var fin = await motion.pos_two();

  var v_s = GOOD_VOXEL_SIZE;
  var r = PROXIMITY_RADIUS / 2;

  var v_x = await voxel.x();
  var x0 = await init.x();
  var xv = (await fin.x()) - (await init.x());

  var v_y = await voxel.y();
  var y0 = (await init.y());
  var yv = (await fin.y()) - (await init.y());

  var low_x, high_x;
  low_x = (v_x - r - x0) / xv;
  high_x = (v_x + v_s + r - x0) / xv;

  var tmp;

  if (xv < 0) {
    tmp = low_x;
    low_x = high_x;
    high_x = tmp;
  }

  var low_y, high_y;
  low_y = (v_y - r - y0) / yv;
  high_y = (v_y + v_s + r - y0) / yv;

  if (yv < 0) {
    tmp = low_y;
    low_y = high_y;
    high_y = tmp;
  }

  return (((xv === 0 && v_x <= x0 + r && x0 - r <= v_x + v_s) /* no motion in x */ ||
           ((low_x <= 1 && 1 <= high_x) || (low_x <= 0 && 0 <= high_x) ||
            (0 <= low_x && high_x <= 1))) &&
          ((yv === 0 && v_y <= y0 + r && y0 - r <= v_y + v_s) /* no motion in y */ ||
           ((low_y <= 1 && 1 <= high_y) || (low_y <= 0 && 0 <= high_y) ||
            (0 <= low_y && high_y <= 1))) &&
          (xv === 0 || yv === 0 || /* no motion in x or y or both */
           (low_y <= high_x && high_x <= high_y) ||
           (low_y <= low_x && low_x <= high_y) ||
           (low_x <= low_y && high_y <= high_x)));
}

async function putIntoMap(voxelMap, voxel, motion) {
  var vec = await voxelMap.get(voxel);
  if (!vec) {
    vec = new som.Vector();
    await voxelMap.put(voxel, vec);
  }
  vec.append(motion);
}

async function voxelHash(position) {
  var xDiv = ((await position.x()) / GOOD_VOXEL_SIZE) | 0;
  var yDiv = ((await position.y()) / GOOD_VOXEL_SIZE) | 0;

  var result = await (await Ruby.exec('Vector2D')).new(
    GOOD_VOXEL_SIZE * xDiv,
    GOOD_VOXEL_SIZE * yDiv
  );

  if ((await position.x()) < 0)
    await result.set_x((await result.x()) - GOOD_VOXEL_SIZE);
  if ((await position.y()) < 0)
    await result.set_y((await result.y()) - GOOD_VOXEL_SIZE);

  return result;
}

async function recurse(voxelMap, seen, nextVoxel, motion) {
  if (!(await isInVoxel(nextVoxel, motion))) {
    return;
  }
  if (await seen.put(nextVoxel, true)) {
    return;
  }

  await putIntoMap(voxelMap, nextVoxel, motion);

  await recurse(voxelMap, seen, await nextVoxel.minus(horizontal), motion);
  await recurse(voxelMap, seen, await nextVoxel.plus(horizontal), motion);
  await recurse(voxelMap, seen, await nextVoxel.minus(vertical), motion);
  await recurse(voxelMap, seen, await nextVoxel.plus(vertical), motion);
  await recurse(voxelMap, seen, await (await nextVoxel.minus(horizontal)).minus(vertical), motion);
  await recurse(voxelMap, seen, await (await nextVoxel.minus(horizontal)).plus(vertical), motion);
  await recurse(voxelMap, seen, await (await nextVoxel.plus(horizontal)).minus(vertical), motion);
  await recurse(voxelMap, seen, await (await nextVoxel.plus(horizontal)).plus(vertical), motion);
}

async function drawMotionOnVoxelMap(voxelMap, motion) {
  var seen = await (await Ruby.exec('RedBlackTree')).new();
  await recurse(voxelMap, seen, await voxelHash(await motion.pos_one()), motion);
}

async function reduceCollisionSet(motions) {
  var voxelMap = await (await Ruby.exec('RedBlackTree')).new();
  await motions.asyncForEach(async function (motion) {
    await drawMotionOnVoxelMap(voxelMap, motion);
  });

  var result = new som.Vector();
  await voxelMap.apply(async function (e) {
    if ((await (await e.value()).size()) > 1) {
      result.append(await e.value());
    }
  });
  return result;
}

function Simulator() {
  this.aircraft = new som.Vector();
}

Simulator.prototype.init = async function (numAircraft) {
  for (var i = 0; i < numAircraft; ++i) {
    this.aircraft.append(await (await Ruby.exec('CallSign')).new(i));
  }
  return this;
}

Simulator.prototype.simulate = async function (time) {
  var frame = new som.Vector();
  for (var i = 0; i < this.aircraft.size(); i += 2) {
    frame.append(await (await Ruby.exec('Aircraft')).new(
      this.aircraft.at(i),
      await (await Ruby.exec('Vector3D')).new(time, Math.cos(time) * 2 + i * 3, 10)
    ));
    frame.append(await (await Ruby.exec('Aircraft')).new(
      this.aircraft.at(i + 1),
      await (await Ruby.exec('Vector3D')).new(time, Math.sin(time) * 2 + i * 3, 10)
    ));
  }
  return frame;
};
