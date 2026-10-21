---@class TetrisInput
---@field update fun(dt: number)
---@field keypressed fun(key: string)
---@field keyreleased fun(key: string)
---@field isSoftDropping fun(): boolean
local input = {}

local game = require("tetris")
local REPEAT_DELAY = 0.22
local REPEAT_INTERVAL = 0.06
local directionKeys = {"left", "right", "a", "d"}
local repeatTimers = {}

local function directionFor(key)
  if key == "left" or key == "a" then
    return -1
  end
  return 1
end

function input.update(dt)
  local state = game.getState()
  if state.paused or state.gameOver then
    return
  end

  dt = math.min(dt, 0.1)
  for _, key in ipairs(directionKeys) do
    local timer = repeatTimers[key]
    if timer then
      timer = timer - dt
      while timer <= 0 do
        game.moveHorizontal(directionFor(key))
        timer = timer + REPEAT_INTERVAL
      end
      repeatTimers[key] = timer
    end
  end
end

function input.keypressed(key)
  if key == "r" then
    game.restart()
    repeatTimers = {}
    return
  end

  if key == "p" then
    game.togglePause()
    return
  end

  local state = game.getState()
  if state.paused or state.gameOver then
    return
  end

  if key == "left" or key == "right" or key == "a" or key == "d" then
    game.moveHorizontal(directionFor(key))
    repeatTimers[key] = REPEAT_DELAY
  elseif key == "down" or key == "s" then
    game.softDrop()
  elseif key == "up" or key == "x" then
    game.rotate(true)
  elseif key == "z" then
    game.rotate(false)
  elseif key == "space" then
    game.hardDrop()
  end
end

function input.keyreleased(key)
  repeatTimers[key] = nil
end

function input.isSoftDropping()
  return love.keyboard.isDown("down", "s")
end

return input
