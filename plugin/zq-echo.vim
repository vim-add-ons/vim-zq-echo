" ·•« Zero-Quote Echo Vim Plugin »•·   ·•« vim-add-ons/zq-echo »•·
" Copyright (c) 2020 « Sebastian Gniazdowski ».
" License: « Gnu GPL v3 ».
"
" A :ZQEcho command that requires literally °ZERO° quoting of its input — it'll
" by itself detect any variables and expressions, differentiate them from
" regular text and then expand constructing the final message. "But :echom also
" 'expands' variables, by design" you'll maybe think. That's true, ZQEcho works
" somewhat in a «reversed» way — it doesn't require to quote regular text
" (unlike echom) ↔ THIS IS THE CANDY — and it takes actions to elevate variables
" and expressions back into their special meaning.
"
" Also, it supports:
" — «multi-color» messages with a custom-message «history»,
" — automatic, easy to activate (ZQEcho! … — simply append the bang +optional
"   count ↔ the timeout) «asynchroneous» display of the message via a
"   «timer-based» callback.
"
" Examples:
" ---------
" :ZQEcho Hello World! You can use any Unicode glyph without quoting: „≈ß•°×∞”
" :2ZQEcho Prepend with a count ↔ a message log-level AND also a distinct color,
" :ZQEcho %1Red %2Green %3Yellow %4Blue %5Magenta %6Cyan %7White %8Black %0Error
" :ZQEcho Above is the short-color format. The long one allows to specify any
"       \ hl-group: %Identifier.Hello world!
" :ZQEcho Provided are color-named hl-groups, like: %gold. %lblue. etc.
"
" Variable/Expression-Examples:
" -----------------------------
" :ZQEcho To print a variable, simply include it, like: g:my_dict['my_field']
" :ZQEcho All data-types will be stringified, so that this works: g:my_dictionary,
"       \ g:my_list, v:argv, etc.
" :ZQEcho Function-like expressions are auto-evaluated, e.g.: toupper("hello!")
" :ZQEcho Include complex expressions by wrapping with parens, e.g.: (rand() % 5)
"
" Asynchroneous-printing:
" -----------------------
" :ZQEcho! I'll be printed from a timer-callback after 10 ms (default) 
" :20ZQEcho! Set time-out to 20 ms ↔ counts >= 15 aren't log-levels, but timeouts

"""""""""""""""""" THE SCRIPT BODY {{{

" ZQEcho — echo-smart command.
command! -nargs=+ -count=4 -bang -bar -complete=var ZQEcho call s:ZeroQuote_ZQEchoCmdImpl(<count>,<q-bang>,expand("<sflnum>"),
            \ map([<f-args>], 's:ZeroQuote_evalArg(exists("l:")?(l:):{},exists("a:")?(a:):{},v:val)' ))

" Messages command.
command! -nargs=? Messages call <Plug>Messages(<q-args>)

" Common highlight definitions.
hi! zq_norm ctermfg=7
hi! zq_blue ctermfg=27
hi! zq_blue1 ctermfg=32
hi! zq_blue2 ctermfg=75
hi! zq_lblue ctermfg=50
hi! zq_lblue2 ctermfg=75 cterm=bold
hi! zq_lblue3 ctermfg=153 cterm=bold
hi! zq_bluemsg ctermfg=123 ctermbg=25 cterm=bold
hi! zq_gold ctermfg=220
hi! zq_yellow ctermfg=190
hi! zq_lyellow ctermfg=yellow cterm=bold
hi! zq_lyellow2 ctermfg=221
hi! zq_lyellow3 ctermfg=226
hi! zq_green ctermfg=green
hi! zq_green2 ctermfg=35
hi! zq_green3 ctermfg=40
hi! zq_green4 ctermfg=82
hi! zq_bgreen ctermfg=green cterm=bold
hi! zq_bgreen2 ctermfg=35 cterm=bold
hi! zq_bgreen3 ctermfg=40 cterm=bold
hi! zq_bgreen4 ctermfg=82 cterm=bold
hi! zq_lgreen ctermfg=lightgreen
hi! zq_lgreen2 ctermfg=118
hi! zq_lgreen3 ctermfg=154
hi! zq_lbgreen ctermfg=lightgreen cterm=bold
hi! zq_lbgreen2 ctermfg=118 cterm=bold
hi! zq_lbgreen3 ctermfg=154 cterm=bold

" Initialize globals.
let g:zq_messages = []

" Session-variables initialization.
let s:ZeroQuote_Messages_state = 0
let [ s:ZeroQuote_ZQEcho, s:ZeroQuote_ZQEcho_idx ] = [ [], -1 ]
let s:ZeroQuote_timers = []

"""""""""""""""""" THE END OF THE SCRIPT BODY }}}

" FUNCTION: s:ZeroQuote_ZQEcho(hl,...) {{{
" 0 - error         LLEV=0 will show only them
" 1 - warning       LLEV=1
" 2 - info          …
" 3 - notice        …
" 4 - debug         …
" 5 - debug2        …
function! s:ZeroQuote_ZQEcho(hl, ...)
    " Log only warnings and errors by default.
    if a:hl < 7 && a:hl > get(g:,'user_menu_log_level', 1) || a:0 == 0
        return
    endif

    " Make a copy of the input.
    let args = deepcopy(type(a:000[0]) == 3 ? a:000[0] : a:000)
    " Strip the line-number argumen for the user- (count>=7) messages.
    if a:hl >= 7 && type(args[0]) == v:t_string &&
                \ args[0] =~ '\v^\[\d*\]$' | let args = args[1:] | endif
    " Normalize higlight/count.
    let hl = a:hl >= 7 ? (a:hl-7) : a:hl

    " Expand any variables and concatenate separated atoms wrapped in parens.
    if ! s:ZeroQuote_Messages_state
        let start_idx = -1
        let new_args = []
        for idx in range(len(args))
            let arg = args[idx]
            " Unclosed paren?
            " Discriminate two special cases: (func() and (func(sub_func())
            if start_idx == -1
                if type(arg) == v:t_string && arg =~# '\v^\(.*([^)]|\([^)]*\)|\([^(]*\([^)]*\)[^)]*\))$'
                    let start_idx = idx
                endif
            " A free, closing paren?
            elseif start_idx >= 0
                if type(arg) == v:t_string && arg =~# '\v^[^(].*\)$' && arg !~ '\v\([^)]*\)$'
                    call add(new_args,eval(join(args[start_idx:idx])))
                    let start_idx = -1
                    continue
                endif
            endif

            if start_idx == -1
                " Compensate for explicit variable-expansion requests or {:ex commands…}, etc.
                let arg = s:ZeroQuote_ExpandVars(arg)

                if type(arg) == v:t_string
                    " A variable?
                    if arg =~# '\v^\s*[svgb]:[a-zA-Z_][a-zA-Z0-9._]*%(\[[^]]+\])*\s*$'
                        let arg = s:ZeroQuote_ExpandVars("{".arg."}")
                    " A function call or an expression wrapped in parens?
                    elseif arg =~# '\v^\s*(([svgb]:)=[a-zA-Z_][a-zA-Z0-9_-]*)=\s*\(.*\)\s*$'
                        let arg = eval(arg)
                    " A \-quoted atom?
                    elseif arg[0] == '\'
                        let arg = arg[1:]
                    endif
                endif

                " Store/save the element.
                call add(new_args, arg)
            endif
        endfor
        let args = new_args
        " Store the message in a custom history.
        call add(g:messages, extend([a:hl], args))
    endif

    " Finally: detect %…. infixes, select color, output the message bit by bit.
    let c = ["Error", "WarningMsg", "gold", "green4", "blue", "None"]
    let [pause,new_msg_pre,new_msg_post] = s:ZeroQuote_GetPrefixValue('p%[ause]', join(args) )
    let msg = new_msg_pre . new_msg_post

    " Pre-process the message…
    let val = ""
    let [arr_hl,arr_msg] = [ [], [] ]
    while val != v:none
        let [val,new_msg_pre,new_msg_post] = s:ZeroQuote_GetPrefixValue('\%', msg)
        let msg = new_msg_post
        if val != v:none
            call add(arr_msg, new_msg_pre)
            call add(arr_hl, val)
        elseif !empty(new_msg_pre)
            if empty(arr_hl)
                call add(arr_msg, "")
                call add(arr_hl, hl)
            endif
            " The final part of the message.
            call add(arr_msg, new_msg_pre)
        endif
    endwhile

    " Clear the message window…
    echon "\r\r"
    echon ''

    " Post-process ↔ display…
    let idx = 0
    while idx < len(arr_hl)
        " Establish the color.
        let hl = !empty(arr_hl[idx]) ? (arr_hl[idx] =~# '^\d\+$' ?
                    \ c[arr_hl[idx]] : arr_hl[idx]) : c[hl]
        let hl = (hl !~# '\v^(-|\d+|zq_[a-z0-9_]+|WarningMsg|Error)$') ? 'zq_'.hl : hl
        let hl = hl == '-' ? 'None' : hl

        " The message part…
        if !empty(arr_msg[idx])
            echon arr_msg[idx]
        endif

        " The color…
        exe 'echohl ' . hl

        " Advance…
        let idx += 1
    endwhile

    " Final message part…
    if !empty(arr_msg[idx:idx])
        echon arr_msg[idx]
    endif
    echohl None

    " 'Submit' the message so that it cannot be deleted with \r…
    if s:ZeroQuote_Messages_state
        echon "\n"
    endif

    if !s:ZeroQuote_Messages_state && !empty(filter(arr_msg,'!empty(v:val)'))
        call s:ZeroQuote_DoPause(pause)
    endif
endfunc
" }}}
"
"""""""""""""""""" HELPER FUNCTIONS {{{
" FUNCTION: s:ZeroQuote_ZQEchoCmdImpl(hl,...) {{{
function! s:ZeroQuote_ZQEchoCmdImpl(hl, bang, linenum, ...)
    if(!empty(a:bang))
        call s:ZeroQuote_DeployDeferred_TimerTriggered_Message(
                    \ { 'm': (a:hl < 7 ? extend(["[".a:linenum."]"], a:000[0]) : a:000[0]) }, 'm', 1)
    else
        if exists("a:000[0][1]") && type(a:000[0][1]) == 1 && a:000[0][1] =~ '\v^\[\d+\]$'
            call s:ZeroQuote_ZQEcho(a:hl, a:000[0])
        else
            call s:ZeroQuote_ZQEcho(a:hl, extend(["[".a:linenum."]"], a:000[0]))
        endif
    endif
endfunc
" }}}
" FUNCTION: s:ZeroQuote_DeployDeferred_TimerTriggered_Message() {{{
function! s:ZeroQuote_DeployDeferred_TimerTriggered_Message(dict,key,...)
    if a:0 && a:1 > 0
        let [s:ZeroQuote_ZQEcho, s:ZeroQuote_ZQEcho_idx] = [ exists("s:ZeroQuote_ZQEcho") ? s:ZeroQuote_ZQEcho : [], exists("s:ZeroQuote_ZQEcho_idx") ? s:ZeroQuote_ZQEcho_idx : 0 ]
    endif
    if has_key(a:dict,a:key)
        let s:ZeroQuote_ZQEcho = a:dict[a:key]
        if a:0 && a:1 >= 0
            call add(s:ZeroQuote_ZQEcho, s:ZeroQuote_ZQEcho)
            call add(s:ZeroQuote_timers, timer_start(a:0 >= 2 ? a:2 : 20, function("s:ZeroQuote_deferredMessageShow")))
            let s:ZeroQuote_ZQEcho_idx = s:ZeroQuote_ZQEcho_idx == -1 ? 0 : s:ZeroQuote_ZQEcho_idx
        else
            if type(s:ZeroQuote_ZQEcho) == 3 || !empty(substitute(s:ZeroQuote_ZQEcho,"^%[^.]*:","","g"))
                if type(s:ZeroQuote_ZQEcho) == 3
                    call s:ZeroQuote_ZQEcho(10, s:ZeroQuote_ZQEcho)
                else
                    10ZQEcho s:ZeroQuote_ZQEcho
                endif
                redraw
            endif
        endif
    endif
endfunc
" }}}
" FUNCTION: s:ZeroQuote_deferredMessageShow(timer) {{{
function! s:ZeroQuote_deferredMessageShow(timer)
    call filter( s:ZeroQuote_timers, 'v:val != a:timer' )
    if type(s:ZeroQuote_ZQEcho[s:ZeroQuote_ZQEcho_idx]) == 3
        call s:ZeroQuote_ZQEcho(10,s:ZeroQuote_ZQEcho[s:ZeroQuote_ZQEcho_idx])
    else
        10ZQEcho s:ZeroQuote_ZQEcho[s:ZeroQuote_ZQEcho_idx]
    endif
    let s:ZeroQuote_ZQEcho_idx += 1
    redraw
endfunc
" }}}
" FUNCTION: s:ZeroQuote_DoPause(pause_value) {{{
function! s:ZeroQuote_DoPause(pause_value)
    if a:pause_value =~ '\v^-=\d+(\.\d+)=$'
        let s:ZeroQuote_pause_value = float2nr(round(str2float(a:pause_value) * 1000.0))
    else
        return
    endif
    if s:ZeroQuote_pause_value =~ '\v^-=\d+$' && s:ZeroQuote_pause_value > 0
        call s:ZeroQuote_PauseAllTimers(1, s:ZeroQuote_pause_value + 10)
        exe "sleep" s:ZeroQuote_pause_value."m"
    endif
endfunc
" }}}
" FUNCTION: s:ZeroQuote_redraw(timer) {{{
function! s:ZeroQuote_redraw(timer)
    call filter( s:ZeroQuote_timers, 'v:val != a:timer' )
    redraw
endfunc
" }}}
" FUNCTION: s:ZeroQuote_PauseAllTimers() {{{
function! s:ZeroQuote_PauseAllTimers(pause,time)
    for t in s:ZeroQuote_timers
        call timer_pause(t,a:pause)
    endfor

    if a:pause && a:time > 0
        " Limit the amount of time of the pause.
        call add(s:ZeroQuote_timers, timer_start(a:time, function("s:ZeroQuote_UnPauseAllTimersCallback")))
    endif
endfunc
" }}}
" FUNCTION: s:ZeroQuote_UnPauseAllTimersCallback() {{{
function! s:ZeroQuote_UnPauseAllTimersCallback(timer)
    call filter( s:ZeroQuote_timers, 'v:val != a:timer' )
    for t in s:ZeroQuote_timers
        call timer_pause(t,0)
    endfor
endfunc
" }}}
" FUNCTION: s:ZeroQuote_evalArg() {{{
function! s:ZeroQuote_evalArg(l,a,arg)
    call extend(l:,a:l)
    ""echom "ENTRY —→ dict:l °" a:l "° —→ dict:a °" a:a "°"
    " 1 — %firstcol.
    " 2 — whole expression, possibly (-l:var)
    " 3 — the optional opening paren
    " 4 — the optional closing paren
    " 5 — %endcol.
    let mres = matchlist(a:arg, '\v^(\%%([0-9-]+\.=|[a-zA-Z0-9_-]*\.))=(([(]=)-=[svbgla]:[a-zA-Z0-9._]+%(\[[^]]+\])*([)]=))(\%%([0-9-]+\.=|[a-zA-Z0-9_-]*\.))=$')
    " Not a variable-expression? → return the original string…
    if empty(mres) || mres[3].mres[4] !~ '^\(()\)\=$'
        "echom "Returning for" a:arg
        return a:arg
    endif
    " Separate-out the core-variable name and the sign.
    let no_dict_arg = substitute(mres[2], '^[(]\=\(-\=\)[svbgla]:\(.\{-}\)[)]\=$', '\1\2', '')
    "echom no_dict_arg "// 1"
    let sign = (no_dict_arg =~ '^-.*') ? -1 : 1
    if sign < 0
        let no_dict_arg = no_dict_arg[1:]
    endif
    "echom no_dict_arg "// 2"
    
    " Fetch the values — any variable-expression except for a:, where only
    " a:simple_forms are allowed, e.g.: no a:complex[s:ZeroQuote_form]…
    if mres[2] =~ '^(\=-\=a:.*'
        "echom "From-dict path ↔" no_dict_arg "—→" get(a:a, no_dict_arg, "<no-such-key>")
        if has_key(a:a, no_dict_arg)
            let value = get(a:a, no_dict_arg, "STRANGE-ERROR…")
            let value = sign < 0 ? -1*value : value
            return mres[1].value.mres[5]
        endif
    elseif exists(substitute(mres[2],'\v(^\(=-=|\)=$)',"","g"))
        "echom "From-eval path ↔" no_dict_arg "↔" eval(mres[2])
        " Via-eval path…
        let value = eval(mres[2])
        if type(value) != v:t_string
            let value = string(value)
        endif
        return mres[1].value.mres[5]
    endif
    " Fall-through path ↔ return of the original string.
    "echom "Fall-through path ↔" no_dict_arg "↔ dict:l °" a:l "° ↔ dict:a °" a:a "°"
    return a:arg
endfunc
" }}}
" FUNCTION: s:ZeroQuote_ExpandVars {{{
" It expands all {:command …'s} and {[sgb]:user_variable's}.
func! s:ZeroQuote_ExpandVars(text_or_texts)
    if type(a:text_or_texts) == v:t_list
        " List input.
        let texts=deepcopy(a:text_or_texts)
        let idx = 0
        for t in texts
            let texts[idx] = s:ZeroQuote_ExpandVars(t)
            let idx += 1
        endfor
        return texts
    elseif type(a:text_or_texts) == v:t_string
        " String input.
        return substitute(a:text_or_texts, '\v\{((:[^}]+|([svgb]\:|\&)[a-zA-Z_]
                        \[a-zA-Z0-9._]*%(\[[^]]+\])*))\}',
                        \ '\=((submatch(1)[0] == ":") ?
                        \ ((submatch(1)[1] == ":") ?
                        \ execute(submatch(1))[1:] :
                            \ execute(submatch(1))[1:0]) :
                                \ (exists(submatch(1)) ?
                                \ eval(submatch(1)) : submatch(1)))', 'g')
    else
        return a:text_or_texts
    endif
endfunc
" }}}
" FUNCTION: s:ZeroQuote_GetPrefixValue(pfx, msg) {{{
func! s:ZeroQuote_GetPrefixValue(pfx, msg)
    if a:pfx =~ '^[a-zA-Z]'
        let mres = matchlist( (type(a:msg) == 3 ? a:msg[0] : a:msg),'\v^(.{-})'.a:pfx.
                    \ ':([^:]*):(.*)$' )
    else
        let mres = matchlist( (type(a:msg) == 3 ? a:msg[0] : a:msg),'\v^(.{-})'.a:pfx.
                    \ '([0-9-]+\.=|[a-zA-Z0-9_-]*\.)(.*)$' )
    endif
    " Special case → a:msg is a List:
    " It's limited functionality — it doesn't allow to determine the message
    " part that preceded and followed the infix (it is just separated out).
    if type(a:msg) == 3 && !empty(mres)
        let cpy = deepcopy(a:msg)
        let cpy[0] = mres[1].mres[3]
        return [substitute(mres[2],'\.$','','g'),cpy,""]
    elseif !empty(mres)
        " Regular case → a:msg is a String
        " It returns the message divided into the part that preceded the infix
        " and that followed it.
        return [ substitute(mres[2],'\.$','','g'), mres[1], mres[3] ]
    else
        return [v:none,a:msg,""]
    endif
endfunc
" }}}
"""""""""""""""""" THE END OF THE HELPER FUNCTIONS }}}

"""""""""""""""""" UTILITY FUNCTIONS {{{
" FUNCTION: Messages(arg=v:none) {{{
function! Messages(arg=v:none)
    if a:arg == "clear"
        let g:messages = []
        return
    endif
    let s:ZeroQuote_Messages_state = 1
    for msg in g:messages
        call s:ZeroQuote_ZQEcho(msg[0],msg[1:])
    endfor
    let s:ZeroQuote_Messages_state = 0
endfunc
" }}}
"""""""""""""""""" THE END OF THE UTILITY FUNCTIONS }}}


" vim:set ft=vim tw=80 foldmethod=marker sw=4 sts=4 et:
