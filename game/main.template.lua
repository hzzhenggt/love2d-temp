--[[
================================================================================
 main.template.lua —— 入口文件模板（空白起点）
================================================================================
 作用：
   这是一个干净的游戏入口模板。当你想从零开始开发自己的游戏时，
   可以把本文件重命名为 main.lua，然后在各个回调函数中填入自己的逻辑。

 使用方法：
   1. 删除示例 demo（eyes 目录）以及现有的 main.lua。
   2. 将本文件重命名为 main.lua。
   3. 在下面标注 "在此编写你的游戏..." 的位置填入代码。

 回调函数说明：
     love.load        —— 启动时执行一次，用于初始化
     love.update(dt)  —— 每帧更新逻辑，dt 为距上一帧的时间（秒）
     love.draw        —— 每帧绘制画面
     love.keypressed  —— 键盘按下事件
     love.touchpressed—— 触摸按下事件
================================================================================
--]]

-- HTTPS 库的全局引用，在 love.load 中按平台动态加载
https = nil

local overlayStats = require("lib.overlayStats") -- 性能统计浮层（第三方库）
local runtimeLoader = require("runtime.loader")   -- 原生库加载器（用于加载 HTTPS）

function love.load()
  https = runtimeLoader.loadHTTPS()
  -- 在此编写你的游戏初始化逻辑
  overlayStats.load() -- 必须最后调用
end

function love.draw()
  -- 在此编写你的游戏绘制逻辑
  overlayStats.draw() -- 必须最后调用
end

function love.update(dt)
  -- 在此编写你的游戏更新逻辑
  overlayStats.update(dt) -- 必须最后调用
end

function love.keypressed(key)
  -- 在非 Web 平台按下 Esc 键退出游戏
  if key == "escape" and love.system.getOS() ~= "Web" then
    love.event.quit()
  else
    overlayStats.handleKeyboard(key) -- 必须最后调用
  end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  overlayStats.handleTouch(id, x, y, dx, dy, pressure) -- 必须最后调用
end
