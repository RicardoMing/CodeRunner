let runner2 = {
            \ 'exe' : 'g++',
            \ 'targetopt' : '-o',
            \ 'opt' : ['-xc++', '-'],
            \ 'usestdin' : 1,
            \ }
call runner#reg_runner('cpp', [runner2, '#TEMP#'])
