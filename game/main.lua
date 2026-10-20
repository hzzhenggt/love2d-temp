--[[
================================================================================
 main.lua —— 游戏入口文件
================================================================================
 作用：
   LÖVE 启动后会调用本文件中定义的若干回调函数，驱动整个游戏循环：
     love.load      —— 启动时执行一次，用于初始化
     love.update(dt)—— 每帧更新逻辑，dt 为距上一帧的时间（秒）
     love.draw      —— 每帧绘制画面
     love.keypressed—— 键盘按下事件
     love.touchpressed—— 触摸按下事件

 本文件是 "eyes"（眼睛）示例 demo 的入口，负责把眼睛场景与
   性能统计浮层（overlayStats）接入游戏循环。
   如需从零开始做自己的游戏，可参考 main.template.lua。
================================================================================
--]]

-- HTTPS 库的全局引用，在 love.load 中按平台动态加载
https = nil

local overlayStats = require("lib.overlayStats")   -- 性能统计浮层（第三方库）
local runtimeLoader = require("runtime.loader")     -- 原生库加载器（用于加载 HTTPS）
local eyes = require("eyes.eyes")                   -- 眼睛示例场景主模块

-- 启动时初始化：加载 HTTPS 库、初始化眼睛场景
function love.load()
  https = runtimeLoader.loadHTTPS()
  eyes.load()
  overlayStats.load() -- 必须最后调用
end

-- 每帧绘制
function love.draw()
  eyes.draw()
  overlayStats.draw() -- 必须最后调用
end

-- 每帧更新逻辑，dt 为帧间隔时间（秒）
function love.update(dt)
  eyes.update(dt)
  overlayStats.update(dt) -- 必须最后调用
end

-- 键盘按下事件处理
function love.keypressed(key)
  -- 在非 Web 平台按下 Esc 键退出游戏
  if key == "escape" and love.system.getOS() ~= "Web" then
    love.event.quit()
  else
    overlayStats.handleKeyboard(key) -- 必须最后调用
  end
end

-- 触摸按下事件处理（移动端 / 触摸屏）
function love.touchpressed(id, x, y, dx, dy, pressure)
  overlayStats.handleTouch(id, x, y, dx, dy, pressure) -- 必须最后调用
end
