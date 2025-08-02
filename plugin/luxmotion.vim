if exists('g:loaded_luxmotion')
  finish
endif
let g:loaded_luxmotion = 1

command! LuxMotionEnable lua require('luxmotion').enable()
command! LuxMotionDisable lua require('luxmotion').disable()
command! LuxMotionToggle lua require('luxmotion').toggle()

command! LuxMotionEnableCursor lua require('luxmotion').enable_cursor()
command! LuxMotionDisableCursor lua require('luxmotion').disable_cursor()
command! LuxMotionEnableScroll lua require('luxmotion').enable_scroll()
command! LuxMotionDisableScroll lua require('luxmotion').disable_scroll()

command! LuxMotionPerformanceEnable lua require('luxmotion.performance').enable()
command! LuxMotionPerformanceDisable lua require('luxmotion.performance').disable()
command! LuxMotionPerformanceToggle lua require('luxmotion').toggle_performance()

if !exists('g:luxmotion_auto_setup')
  let g:luxmotion_auto_setup = 1
endif

if g:luxmotion_auto_setup
  lua require('luxmotion').setup()
endif