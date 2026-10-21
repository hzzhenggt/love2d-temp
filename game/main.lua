local overlayStats = require("lib.overlayStats")
local tetris = require("tetris")
local tetrisInput = require("tetris.input")
local tetrisRenderer = require("tetris.renderer")

function love.load()
  love.keyboard.setKeyRepeat(false)
  tetris.load()
  tetrisRenderer.load()
  overlayStats.load()
end

function love.draw()
  tetrisRenderer.draw()
  overlayStats.draw()
end

function love.update(dt)
  tetrisInput.update(dt)
  tetris.update(dt, tetrisInput.isSoftDropping())
  overlayStats.update(dt)
end

function love.keypressed(key)
  if key == "escape" and love.system.getOS() ~= "Web" then
    love.event.quit()
    return
  end

  tetrisInput.keypressed(key)
  overlayStats.handleKeyboard(key)
end

function love.keyreleased(key)
  tetrisInput.keyreleased(key)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  overlayStats.handleTouch(id, x, y, dx, dy, pressure)
end
