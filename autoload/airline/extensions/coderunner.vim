" MIT License. Copyright (c) 2013-2018 Bailey Ling et al.
" vim: et ts=2 sts=2 sw=2

scriptencoding utf-8

" Due to some potential rendering issues, the use of the `space` variable is
" recommended.
let s:spc = g:airline_symbols.space

function! airline#extensions#coderunner#init(ext)
  call a:ext.add_statusline_func('airline#extensions#coderunner#apply')
  " call a:ext.add_inactive_statusline_func('airline#extensions#coderunner#unapply')
endfunction

function! airline#extensions#coderunner#apply(...)
  if &filetype == 'CodeRunner'
    let w:airline_section_a = 'Runner'
    let w:airline_section_c = '%{runner#status()}'
    let w:airline_section_x = ''
    let w:airline_section_y = ''
    let w:airline_section_z = ''
  endif
endfunction
