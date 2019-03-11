let runner1 = {
            \ 'exe' : 'gcc',
            \ 'targetopt' : '-o',
            \ 'opt' : ['-xc', '-'],
            \ 'usestdin' : 1,
            \ }
call runner#reg_runner('c', [runner1, '#TEMP#'])
