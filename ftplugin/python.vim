function! s:getexe() abort
    let line = getline(1)
    if line =~# '^#!'
        let exe = split(line)
        let exe[0] = exe[0][2:]
        return exe
    endif
    return ['python']
endfunction

call runner#reg_runner('python', {
            \ 'exe' : function('s:getexe'),
            \ 'opt' : ['-'],
            \ 'usestdin' : 1,
            \ })
