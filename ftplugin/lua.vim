let luaexe = filter(['lua53', 'lua52', 'lua51'], 'executable(v:val)')
let exe_lua = empty(luaexe) ? 'lua' : luaexe[0]
call runner#reg_runner('lua', {
            \ 'exe' : exe_lua,
            \ 'opt' : ['-'],
            \ 'usestdin' : 1,
            \ })
