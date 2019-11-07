if exists('g:coderunner_loaded')
    finish
else
    let g:coderunner_loaded = 1
endif

function! s:HandleOnlyWindow() abort
    if winnr('$') == 1 && bufwinnr('__runner__') == 1
        if tabpagenr('$') == 1
            noautocmd keepalt bdelete
            quit
        else
            call runner#close()
            call airline#update_statusline()
        endif
    endif
endfunction

augroup CodeRunner
    autocmd!
    autocmd WinEnter __runner__ call s:HandleOnlyWindow()
augroup END

nmap <silent> <Plug>CodeRunner :call runner#open()<CR>

if !exists(':Runner')
    command! -nargs=0 Runner call runner#open()
endif
