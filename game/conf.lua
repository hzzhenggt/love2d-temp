--[[
================================================================================
 conf.lua —— LÖVE 游戏配置文件
================================================================================
 作用：
   LÖVE 在启动时会最先加载本文件，用于配置窗口、音频、模块开关等运行参数。
   详见官方文档：https://love2d.org/wiki/Config_Files

 本文件主要做三件事：
   1. 检测是否处于 VSCode 本地调试模式，若是则启动 lldebugger。
   2. 从 product.env 读取产品配置（游戏与 CI 构建共享这些设置）。
   3. 在 love.conf(t) 中设置窗口尺寸、标题、音频、启用的模块等。

 说明：本文件为 LÖVE 模板自带示例的一部分。
================================================================================
--]]

-- 是否处于调试模式：仅当 VSCode 调试器环境变量为 "1" 且启动参数为 "debug" 时成立
local IS_DEBUG = os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" and arg[2] == "debug"
if IS_DEBUG then
  require("lldebugger").start()

  -- 调试模式下重写错误处理函数，便于调试器捕获错误堆栈
  function love.errorhandler(msg)
    error(msg, 2)
  end
end

-- 读取产品配置（product.env）
-- 这些配置在游戏运行时与 CI 构建流程之间共享
product_config = {}
for line in love.filesystem.lines("product.env") do
  -- 跳过注释行（以 # 开头）和空行
  if not (line:match("^%s*#") or line:match("^%s*$")) then
    local key, value = line:match("([^=]+)=(.*)")
    if key then
      -- 去掉值两侧可能存在的双引号
      product_config[key] = value:match('^"?(.-)"?$')
    end
  end
end

-- LÖVE 配置回调函数，t 为可修改的配置表
-- https://love2d.org/wiki/Config_Files
function love.conf(t)
  t.identity              = product_config["PRODUCT_ID"]   -- 存档目录名（取自产品配置）
  t.appendidentity        = false
  t.version               = product_config["LOVE_VERSION"] -- 目标 LÖVE 版本

  -- 注意：若 t.console 设为 true，则调试器将无法正常工作
  t.console               = false
  t.accelerometerjoystick = false
  t.externalstorage       = false
  t.gammacorrect          = false

  t.audio.mic             = product_config["AUDIO_MIC"]    -- 是否请求麦克风权限
  t.audio.mixwithsystem   = false

  -- 窗口相关配置
  t.window.title          = product_config["PRODUCT_NAME"] -- 窗口标题
  t.window.icon           = nil
  t.window.width          = 1920
  t.window.height         = 1080
  t.window.borderless     = false
  t.window.resizable      = false
  t.window.minwidth       = 1
  t.window.minheight      = 1
  t.window.fullscreen     = false
  t.window.fullscreentype = "desktop"
  t.window.vsync          = 1
  t.window.msaa           = 0
  t.window.depth          = nil
  t.window.stencil        = nil
  t.window.display        = 1
  t.window.highdpi        = true
  t.window.usedpiscale    = true
  t.window.x              = nil
  t.window.y              = nil

  -- 启用的 LÖVE 模块（按需开关，可减少不必要的初始化）
  t.modules.audio         = true
  t.modules.data          = true
  t.modules.event         = true
  t.modules.font          = true
  t.modules.graphics      = true
  t.modules.image         = true
  t.modules.joystick      = true
  t.modules.keyboard      = true
  t.modules.math          = true
  t.modules.mouse         = true
  t.modules.physics       = true
  t.modules.sound         = true
  t.modules.system        = true
  t.modules.thread        = true
  t.modules.timer         = true
  t.modules.touch         = true
  t.modules.video         = true
  t.modules.window        = true
end
