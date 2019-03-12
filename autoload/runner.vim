let s:self = {}
let s:self.jobs = {}
let s:self._message = []

function! s:self.warn(...) abort
    if len(a:000) == 0
        echohl WarningMsg | echom 'Current version do not support job feature, fallback to sync system()' | echohl None
    elseif len(a:000) == 1 && type(a:1) == type('')
        echohl WarningMsg | echom a:1| echohl None
    else
    endif
endfunction

function! s:self.start(argv, ...) abort
    try
        if len(a:000) > 0
            let job = jobstart(a:argv, a:1)
        else
            let job = jobstart(a:argv)
        endi
    catch /^Vim\%((\a\+)\)\=:E903/
        return -1
    endtry
    if job > 0
        let msg = ['process '. jobpid(job), ' run']
        call extend(self.jobs, {job : msg})
    else
        if job == -1
            call add(self._message, 'Failed to start job:' . (type(a:argv) == 3 ? a:argv[0] : a:argv) . ' is not executeable')
        elseif job == 0
            call add(self._message, 'Failed to start job: invalid arguments')
        endif
    endif
    return job
endfunction

function! s:self.stop(id) abort
    if has_key(self.jobs, a:id)
        call jobstop(a:id)
        call remove(self.jobs, a:id)
    else
        call self.warn('[job API] Failed to stop job :' . a:id)
    endif
endfunction

function! s:self.send(id, data) abort
    if has_key(self.jobs, a:id)
        if type(a:data) == type('')
            call jobsend(a:id, [a:data, ''])
        else
            call jobsend(a:id, a:data)
        endif
    endif
endfunction

function! s:self.chanclose(id, type) abort
    call chanclose(a:id, a:type)
endfunction

function! s:self.buf_set_lines(buffer, start, end, strict_indexing, replacement) abort
    let ma = getbufvar(a:buffer, '&ma')
    call setbufvar(a:buffer,'&ma', 1)
    call nvim_buf_set_lines(a:buffer, a:start, a:end, a:strict_indexing, a:replacement)
    call setbufvar(a:buffer,'&ma', ma)
endfunction

function! s:self.unify_path(path, ...) abort
    let mod = a:0 > 0 ? a:1 : ':p'
    let path = resolve(fnamemodify(a:path, mod . ':gs?[\\/]?/?'))
    if isdirectory(path) && path[-1:] !=# '/'
        return path . '/'
    elseif a:path[-1:] ==# '/' && path[-1:] !=# '/'
        return path . '/'
    else
        return path
    endif
endfunction

function! s:self.trim(str) abort
    let str = substitute(a:str, '\s*$', '', 'g')
    return substitute(str, '^\s*', '', 'g')
endfunction


" ==============================================================================


let s:runners = {}

let s:bufnr = 0

function! s:open_win() abort
    if s:bufnr != 0 && bufexists(s:bufnr)
        exe 'bd ' . s:bufnr
    endif
    botright split __runner__
    let lines = &lines * 30 / 100
    exe 'resize ' . lines
    setlocal buftype=nofile bufhidden=wipe nobuflisted nolist nomodifiable
                \ noswapfile
                \ nowrap
                \ cursorline
                \ nospell
                \ nonu
                \ norelativenumber
                \ winfixheight
                \ nomodifiable
    set filetype=CodeRunner
    nnoremap <silent><buffer> q :call runner#close()<cr>
    nnoremap <silent><buffer> i :call <SID>insert()<cr>
    let s:bufnr = bufnr('%')
    wincmd p
endfunction

function! s:insert() abort
    call inputsave()
    let input = input('input > ')
    if !empty(input) && s:status.is_running == 1
        call s:self.send(s:job_id, input)
    endif
    normal! :
    call inputrestore()
endfunction

let s:target = ''

function! s:async_run(runner) abort
    if type(a:runner) == type('')
        " the runner is a string, the %s will be replaced as a file name.
        try
            let cmd = printf(a:runner, get(s:, 'selected_file', bufname('%')))
        catch
            let cmd = a:runner
        endtry
        " call SpaceVim#logger#info('   cmd:' . string(cmd))
        call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 3, 0, ['[Running] ' . cmd, '', repeat('-', 20)])
        let s:lines += 3
        let s:start_time = reltime()
        let s:job_id =  s:self.start(cmd,{
                    \ 'on_stdout' : function('s:on_stdout'),
                    \ 'on_stderr' : function('s:on_stderr'),
                    \ 'on_exit' : function('s:on_exit'),
                    \ })
    elseif type(a:runner) == type([])
        " the runner is a list
        " the first item is compile cmd, and the second one is running cmd.
        let s:target = s:self.unify_path(tempname(), ':p')
        if type(a:runner[0]) == type({})
            if type(a:runner[0].exe) == 2
                let exe = call(a:runner[0].exe, [])
            elseif type(a:runner[0].exe) ==# type('')
                let exe = [a:runner[0].exe]
            endif
            let usestdin = get(a:runner[0], 'usestdin', 0)
            let compile_cmd = exe + [get(a:runner[0], 'targetopt', '')] + [s:target]
            if usestdin
                let compile_cmd = compile_cmd + a:runner[0].opt
            else
                let compile_cmd = compile_cmd + a:runner[0].opt + [get(s:, 'selected_file', bufname('%'))]
            endif
        else
            let compile_cmd = substitute(printf(a:runner[0], bufname('%')), '#TEMP#', s:target, 'g')
        endif
        call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 3, 0, [
                    \ '[Compile] ' . join(compile_cmd) . (usestdin ? ' STDIN' : ''),
                    \ '[Running] ' . s:target,
                    \ '',
                    \ repeat('-', 20)])
        let s:lines += 4
        let s:start_time = reltime()
        let s:job_id =  s:self.start(compile_cmd,{
                    \ 'on_stdout' : function('s:on_stdout'),
                    \ 'on_stderr' : function('s:on_stderr'),
                    \ 'on_exit' : function('s:on_compile_exit'),
                    \ })
        if usestdin
            let range = get(a:runner[0], 'range', [1, '$'])
            call s:self.send(s:job_id, call('getline', range))
            call s:self.chanclose(s:job_id, 'stdin')
        endif
    elseif type(a:runner) == type({})
        " the runner is a dict
        " keys:
        "   exe : function, return a cmd list
        "         string
        "   usestdin: true, use stdin
        "             false, use file name
        "   range: empty, whole buffer
        "          getline(a, b)
        if type(a:runner.exe) == 2
            let exe = call(a:runner.exe, [])
        elseif type(a:runner.exe) ==# type('')
            let exe = [a:runner.exe]
        endif
        let usestdin = get(a:runner, 'usestdin', 0)
        if usestdin
            let cmd = exe + a:runner.opt
        else
            let cmd = exe + a:runner.opt + [get(s:, 'selected_file', bufname('%'))]
        endif
        " call SpaceVim#logger#info('   cmd:' . string(cmd))
        call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 3, 0, ['[Running] ' . join(cmd) . (usestdin ? ' STDIN' : ''), '', repeat('-', 20)])
        let s:lines += 3
        let s:start_time = reltime()
        let s:job_id =  s:self.start(cmd,{
                    \ 'on_stdout' : function('s:on_stdout'),
                    \ 'on_stderr' : function('s:on_stderr'),
                    \ 'on_exit' : function('s:on_exit'),
                    \ })
        if usestdin
            let range = get(a:runner, 'range', [1, '$'])
            call s:self.send(s:job_id, call('getline', range))
            call s:self.chanclose(s:job_id, 'stdin')
        endif
    endif
    if s:job_id > 0
        let s:status = {
                    \ 'is_running' : 1,
                    \ 'is_exit' : 0,
                    \ 'has_errors' : 0,
                    \ 'exit_code' : 0
                    \ }
    endif
endfunction

function! s:on_compile_exit(id, data, event) abort
    if a:data == 0
        let s:job_id =  s:self.start(s:target,{
                    \ 'on_stdout' : function('s:on_stdout'),
                    \ 'on_stderr' : function('s:on_stderr'),
                    \ 'on_exit' : function('s:on_exit'),
                    \ })
        if s:job_id > 0
            let s:status = {
                        \ 'is_running' : 1,
                        \ 'is_exit' : 0,
                        \ 'has_errors' : 0,
                        \ 'exit_code' : 0
                        \ }
        endif
    else
        let s:end_time = reltime(s:start_time)
        let s:status.is_exit = 1
        let s:status.is_running = 0
        let s:status.exit_code = a:data
        let done = ['', '[Done] exited with code=' . a:data . ' in ' . s:self.trim(reltimestr(s:end_time)) . ' seconds']
        call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, done)
        call s:handle_error()
    endif
    call s:update_statusline()
endfunction

function! s:update_statusline() abort
    redrawstatus!
endfunction

function! runner#reg_runner(ft, runner) abort
    let s:runners[a:ft] = a:runner
    let desc = '[' . a:ft . '] ' . string(a:runner)
    let cmd = "call runner#set_language('" . a:ft . "')"
    call add(g:unite_source_menu_menus.RunnerLanguage.command_candidates, [desc,cmd])
endfunction

function! runner#get(ft) abort
    return deepcopy(get(s:runners, a:ft , ''))
endfunction

function! runner#open(...) abort
    let s:lines = 0
    let s:status = {
                \ 'is_running' : 0,
                \ 'is_exit' : 0,
                \ 'has_errors' : 0,
                \ 'exit_code' : 0
                \ }
    let runner = get(a:000, 0, get(s:runners, &filetype, ''))
    let s:filename = expand('%')
    if !empty(runner)
        let s:selected_language = &filetype
        call s:open_win()
        call s:async_run(runner)
        call s:update_statusline()
    else
        let s:selected_language = get(s:, 'selected_language', '')
    endif
endfunction

" remove ^M at the end of each
let s:_out_data = ['']
function! s:on_stdout(job_id, data, event) abort
    let s:_out_data[-1] .= a:data[0]
    call extend(s:_out_data, a:data[1:])
    if s:_out_data[-1] ==# ''
        call remove(s:_out_data, -1)
        let lines = s:_out_data
    else
        let lines = s:_out_data
    endif
    if !empty(lines)
        let lines = map(lines, "substitute(v:val, '$', '', 'g')")
        call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, lines)
    endif
    let s:lines += len(lines)
    let s:_out_data = ['']
    call s:update_statusline()
endfunction

let s:_err_data = ['']
function! s:on_stderr(job_id, data, event) abort
    let s:_out_data[-1] .= a:data[0]
    call extend(s:_out_data, a:data[1:])
    if s:_out_data[-1] ==# ''
        call remove(s:_out_data, -1)
        let lines = s:_out_data
    else
        let lines = s:_out_data
    endif
    if !empty(lines)
        call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, lines)
    endif
    let s:lines += len(lines)
    let s:_out_data = ['']
    call s:update_statusline()
endfunction

function! s:on_exit(job_id, data, event) abort
    let s:end_time = reltime(s:start_time)
    let s:status.is_exit = 1
    let s:status.is_running = 0
    let s:status.exit_code = a:data
    let done = ['', '[Done] exited with code=' . a:data . ' in ' . s:self.trim(reltimestr(s:end_time)) . ' seconds']
    call s:self.buf_set_lines(s:bufnr, s:lines , s:lines + 1, 0, done)
    if a:data != 0
        call s:handle_error()
    endif
    call s:update_statusline()
endfunction

function! s:handle_error() abort
    cexpr substitute(join(getbufline(s:bufnr, 1, '$'), "\n"), '<stdin>', s:filename, 'g')
    call runner#close()
    let l:lines = &lines * 30 / 100
    let l:status_info = runner#status()
    call setqflist([], 'r', {'title': l:status_info})
    exe 'copen ' . l:lines
endfunction

function! runner#status() abort
    if s:status.is_running == 1
    elseif s:status.is_exit == 1
        return 'exit code: ' . s:status.exit_code
                    \ . '    time: ' . s:self.trim(reltimestr(s:end_time))
                    \ . '    language: ' . get(s:, 'selected_language', &ft)
    endif
    return ''
endfunction

function! runner#close() abort
    if s:status.is_exit == 0
        call s:self.stop(s:job_id)
    endif
    exe 'bd ' s:bufnr
endfunction

function! runner#select_file() abort
    let s:lines = 0
    let s:status = {
                \ 'is_running' : 0,
                \ 'is_exit' : 0,
                \ 'has_errors' : 0,
                \ 'exit_code' : 0
                \ }
    let s:selected_file = browse(0,'select a file to run', getcwd(), '')
    let runner = get(a:000, 0, get(s:runners, &filetype, ''))
    let s:selected_language = &filetype
    if !empty(runner)
        " call SpaceVim#logger#info('Code runner startting:')
        " call SpaceVim#logger#info('selected file :' . s:selected_file)
        call s:open_win()
        call s:async_run(runner)
        call s:update_statusline()
    endif
endfunction

let g:unite_source_menu_menus =
            \ get(g:,'unite_source_menu_menus',{})
let g:unite_source_menu_menus.RunnerLanguage = {'description':
            \ 'Custom mapped keyboard shortcuts                   [SPC] p p'}
let g:unite_source_menu_menus.RunnerLanguage.command_candidates =
            \ get(g:unite_source_menu_menus.RunnerLanguage,'command_candidates', [])

function! runner#select_language() abort
    " @todo use denite or unite to select language
    " and set the s:selected_language
    " the all language is keys(s:runners)
    Denite menu:RunnerLanguage
endfunction

function! runner#set_language(lang) abort
    " @todo use denite or unite to select language
    " and set the s:selected_language
    " the all language is keys(s:runners)
    let s:selected_language = a:lang
endfunction
