--[[
================================================================================
 eyes/audio.lua —— 眼睛场景音频模块
================================================================================
 作用：
   管理眼睛场景中的全部声音，包括：
     1. 环境火焰音：以左右两个独立声源实现真正的立体声，并随光标位置
        做左右声道的平滑交叉淡化与音量变化。
     2. 触碰音效：当光标触碰到眼睛时，随机播放一组 "aargh" 音效之一，
        并通过冷却时间与状态标志避免重复触发、保证连续触碰时能衔接播放。

 主要状态（soundState）：
     currentSound       当前正在播放的音效声源
     soundPlaying       是否有音效正在播放
     soundJustFinished  音效是否刚刚播放完毕（用于连续触碰时接着播放）
     lastTouchTime      上次触发音效的时间
     touchCooldown      触发音效的冷却时间（秒）
     lastTouchingState  上一帧的触碰状态
================================================================================
--]]

---@class EyesAudio 管理眼睛场景音频的模块
local audio = {
  -- 音效集合
  sounds = {},

  -- 环境火焰音
  ambientFireSound = nil,

  -- 音效播放状态跟踪
  soundState = {
    currentSound = nil,
    soundPlaying = false,
    soundJustFinished = false,
    lastTouchTime = 0,
    touchCooldown = 0.5,
    lastTouchingState = false
  }
}

---加载全部可用的 "aargh" 音效
---@return table 音效声源数组
local function loadSoundEffects()
  local sounds = {}
  for i = 1, 7 do
    local soundPath = "eyes/sfx/aargh" .. i .. ".ogg"
    table.insert(sounds, love.audio.newSource(soundPath, "static"))
  end
  return sounds
end

---以左右两个独立单声道声源加载环境火焰音，实现真正的立体声混音
---@return table 包含左右声道火焰音的表
local function loadAmbientFireSound()
  local soundPath = "eyes/sfx/fire.ogg"
  -- 创建该音效的两个实例
  local leftChannel = love.audio.newSource(soundPath, "stream")
  local rightChannel = love.audio.newSource(soundPath, "stream")

  -- 两个声源均设为循环播放
  leftChannel:setLooping(true)
  rightChannel:setLooping(true)

  -- 将两个声源分别硬声像到左右两侧
  leftChannel:setPosition(-1, 0, 0)
  rightChannel:setPosition(1, 0, 0)

  return {
    left = leftChannel,
    right = rightChannel
  }
end

---随机播放一个 "aargh" 音效
---@param sounds table 音效声源数组
---@return love.Source 正在播放的音效声源
local function playRandomSound(sounds)
  -- 随机选择一个音效
  local index = love.math.random(1, #sounds)
  local sound = sounds[index]

  -- 先停止可能正在播放的上一个实例
  sound:stop()

  -- 设置为非循环（只播放一次）
  sound:setLooping(false)

  -- 播放音效
  sound:play()

  return sound
end

---根据眼睛触碰情况更新音效状态
---@param state table 当前眼睛状态
---@param sounds table 音效声源数组
---@param soundState table 音效状态跟踪表
local function updateSoundState(state, sounds, soundState)
  local wasTouching = soundState.lastTouchingState
  local currentTime = love.timer.getTime()
  local cooldownElapsed = (currentTime - soundState.lastTouchTime) > soundState.touchCooldown

  -- 以下情况播放音效：
  -- 1. 刚刚开始触碰眼睛，或
  -- 2. 上一个音效刚播放完且仍在持续触碰眼睛
  -- 并且上述两种情况都要满足：当前没有音效在播放，且冷却时间已过
  if ((state.touching and not wasTouching) or
      (state.touching and soundState.soundJustFinished)) and
     not soundState.soundPlaying and cooldownElapsed then

    soundState.soundPlaying = true
    soundState.soundJustFinished = false -- 使用后重置该标志
    soundState.lastTouchTime = currentTime

    -- 随机播放一个音效并记录下来
    soundState.currentSound = playRandomSound(sounds)
  end

  -- 若不再触碰，则重置"刚播放完"的标志
  if not state.touching then
    soundState.soundJustFinished = false
  end

  -- 保存本帧触碰状态，供下一帧比较
  soundState.lastTouchingState = state.touching
end

---根据光标位置更新音频系统的音量与声像
---@param ambientFireSound table 包含左右声道火焰音的表
---@param x number 当前光标 X 位置
---@param y number 当前光标 Y 位置
---@param windowWidth number 窗口宽度
---@param windowHeight number 窗口高度
local function updateAudioSystem(ambientFireSound, x, y, windowWidth, windowHeight)
  if not ambientFireSound then return end

  -- 用平滑交叉淡化营造均衡的立体声效果
  local normalizedX = x / windowWidth

  -- 为左右声道计算平滑的音量：
  -- 光标靠左（normalizedX 接近 0）时左声道更响
  -- 光标靠右（normalizedX 接近 1）时右声道更响
  -- 两个声道都至少保留 30% 音量，以维持连续的立体声
  local leftVolume = math.max(0.3, 1.0 - (normalizedX * 0.7))
  local rightVolume = math.max(0.3, 0.3 + (normalizedX * 0.7))

  -- 根据与屏幕中心的接近程度计算整体音量
  local centerX = windowWidth / 2
  local centerY = windowHeight / 2
  local distanceFromCenterX = 1.0 - math.abs(x - centerX) / centerX
  local distanceFromCenterY = 1.0 - math.abs(y - centerY) / centerY
  local volumeMultiplier = distanceFromCenterX * distanceFromCenterY
  local baseVolume = 0.5 + (volumeMultiplier * 0.7)

  -- 将计算出的音量应用到左右声道
  ambientFireSound.left:setVolume(leftVolume * baseVolume)
  ambientFireSound.right:setVolume(rightVolume * baseVolume)
end

-- 公共 API
---初始化音频系统
function audio:load()
  -- 加载触碰音效
  self.sounds = loadSoundEffects()

  -- 加载并开始播放环境火焰音（真正的立体声）
  self.ambientFireSound = loadAmbientFireSound()
  self.ambientFireSound.left:play()
  self.ambientFireSound.right:play()
end

---更新音频系统
---@param dt number 距上一帧的时间
---@param state table 当前眼睛状态
---@param x number 当前光标 X 位置
---@param y number 当前光标 Y 位置
function audio:update(dt, state, x, y)
  -- 根据眼睛状态更新音效
  updateSoundState(state, self.sounds, self.soundState)

  -- 检查音效是否已播放完毕
  if self.soundState.currentSound and not self.soundState.currentSound:isPlaying() then
    -- 音效播放结束
    self.soundState.currentSound = nil
    self.soundState.soundPlaying = false
    self.soundState.soundJustFinished = true -- 播放结束时置位该标志
  end

  -- 更新音频的声像与音量
  local windowWidth = love.graphics.getWidth()
  local windowHeight = love.graphics.getHeight()
  updateAudioSystem(self.ambientFireSound, x, y, windowWidth, windowHeight)
end

---停止所有音频并清理资源
function audio:stop()
  if self.ambientFireSound then
    if self.ambientFireSound.left then
      self.ambientFireSound.left:stop()
    end
    if self.ambientFireSound.right then
      self.ambientFireSound.right:stop()
    end
  end

  if self.soundState.currentSound then
    self.soundState.currentSound:stop()
  end
end

return audio
