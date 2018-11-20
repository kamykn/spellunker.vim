" Vim plugin of checking words spell on the code.
" Version 1.0.0
" Author kamykn
" License VIM LICENSE

scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

" 大文字小文字を区別して単語リストを取得
function! s:get_word_list(window_text_list)
	let l:word_list = []

	for line in a:window_text_list
		let l:word_list = s:get_word_list_in_line(line, l:word_list)
	endfor

	return l:word_list
endfunction

function! s:get_word_list_in_line(line, word_list)
	let l:word_list = a:word_list
	let l:line = s:convert_controll_charactor_to_space(a:line)

	while 1
		" キャメルケース、パスカルケース、スネークケースの抜き出し
		" ex) camelCase, PascalCase, snake_case, lowercase
		let l:match_target_word = matchstr(l:line, '\v([A-Za-z_]+)\C')

		if l:match_target_word == ""
			break
		endif

		let l:line = s:cut_text_word_before(l:line, l:match_target_word)
		let l:find_word_list = s:code_to_words(l:match_target_word)

		for word in l:find_word_list
			if index(l:word_list, word) == -1
				call add(l:word_list, word)
			endif
		endfor
	endwhile

	return l:word_list
endfunction

function! s:filter_spell_bad_list(word_list)
	let l:spell_bad_list  = []

	" 言語別ホワイトリストの取得
	let l:white_list_for_lang = []
	try
		let l:filetype = &filetype
		execute 'let l:white_list_for_lang = s:filter_list_char_length(white_list_' . l:filetype . '#init_white_list())'
	catch
		" 読み捨て
	endtry

	let l:spellunker_white_list = s:filter_list_char_length(g:spellunker_white_list)

	for orig_word in s:filter_list_char_length(a:word_list)
		let l:lowercase_word = tolower(orig_word)

		if index(l:spellunker_white_list, l:lowercase_word) >= 0
			continue
		endif

		if index(l:white_list_for_lang, l:lowercase_word) >= 0
			continue
		endif

		let [l:spell_bad_word, l:error_type] = spellbadword(l:lowercase_word)

		" 登録は元のケースで行う。辞書登録とそのチェックにかけるときのみlowerケースになる。
		" 元々ここでlowercaseだけ管理し、lower,UPPER,UpperCamelCaseをmatchadd()していたが、
		" 最少のマッチだけを登録させる為、ここで実際に引っかかるものを登録させ、
		" これらをmatchaddさせる。
		if l:spell_bad_word != '' && index(l:spell_bad_list, orig_word) == -1
			call add(l:spell_bad_list, orig_word)
		endif
	endfor

	return l:spell_bad_list
endfunction

" 特定の文字数以上のみ返す
function! s:filter_list_char_length(word_list)
	let l:filtered_word_list = []

	for word in a:word_list
		if strlen(word) < g:spellunker_target_min_char_len
			continue
		endif

		call add(l:filtered_word_list, word)
	endfor

	return l:filtered_word_list
endfunction

function! s:code_to_words(line_of_code)
	let l:split_by   = ' '
	let l:words_list = []

	" 単語ごとに空白で区切った後にsplitで単語だけの配列を作る
	" ex) spellBadWord -> spell Bad Word -> ['spell', 'Bad', 'Word']
	" ex) spell_bad_word -> spell bad word -> ['spell', 'bad', 'word']

	" ABC_DEF -> ABC DEF
	let l:code_for_split = substitute(a:line_of_code, '_', l:split_by, "g")

	" ABCdef -> AB Cdef
	" abcAPI -> abc API
	let l:code_for_split = substitute(l:code_for_split, '\v([A-Z\s]@<![A-Z]|[A-Z][a-z])\C', l:split_by . "\\1", "g")

	" AA__BB -> AA  BB -> AA BB
	let l:code_for_split = substitute(l:code_for_split, '\v\s+', l:split_by, "g")

	return split(l:code_for_split, l:split_by)
endfunction

function! s:search_target_word()
	let l:cursor_position = col('.')
	let l:line = getline('.')

	" get_word_list_in_lineの中で制御文字を取り除いたりしている
	let l:word_list = s:get_word_list_in_line(l:line, [])

	" 単語のポジションリストを返して、ポジションスタート + 単語長の中にcurposがあればそこが現在位置
	for word in l:word_list
		let l:word_index_list = s:find_word_index_list(l:line, word)
		for target_word_start_pos in l:word_index_list
			if target_word_start_pos <= l:cursor_position && l:cursor_position <= target_word_start_pos + strlen(word)
				return word
			endif
		endfor
	endfor

	echo "There is no word under the cursor."
	return ''
endfunction


function! s:find_word_index_list(line_str, search_word)
	" 単語のポジションリストを返して、ポジションスタート + 単語長の中にcurposがあればそこが現在位置

	let l:cword_length         = strlen(a:search_word)
	let l:find_word_index_list = []
	let l:line_str             = a:line_str

	while 1
		let l:tmp_cword_pos = stridx(l:line_str, a:search_word)
		if l:tmp_cword_pos < 0
			break
		endif

		call add(l:find_word_index_list, l:tmp_cword_pos)
		let l:line_str = strpart(l:line_str, l:tmp_cword_pos + l:cword_length)
	endwhile

	return l:find_word_index_list
endfunction

function! s:format_spell_suggest_list(spell_suggest_list, target_word)
	" 変換候補選択用リスト
	let l:spell_suggest_list_for_input_list = []
	" 変換候補リプレイス用リスト
	let l:spell_suggest_list_for_replace   = []

	let l:select_index_strlen = strlen(len(a:spell_suggest_list))

	let l:i = 1
	for s in a:spell_suggest_list
		let l:index_str = printf("%" . l:select_index_strlen . "d", l:i) . ': '

		" 記号削除
		let s = substitute(s, '\.', " ", "g")

		" 2単語の場合連結
		if stridx(s, ' ') > 0
			let s = substitute(s, '\s', ' ', 'g')
			let l:suggest_words = split(s, ' ')
			let s = ''
			for w in l:suggest_words
				let s = s . s:to_first_char_upper(w)
			endfor
		endif

		" 先頭大文字小文字
		if match(a:target_word[0], '\v[A-Z]\C') == -1
			let s = tolower(s)
		else
			let s = s:to_first_char_upper(s)
		endif

		call add(l:spell_suggest_list_for_replace, s)
		call add(l:spell_suggest_list_for_input_list, l:index_str . '"' . s . '"')
		let l:i += 1
	endfor

	return [l:spell_suggest_list_for_input_list, l:spell_suggest_list_for_replace]
endfunction

function! s:cut_text_word_before (text, word)
	let l:found_pos = stridx(a:text, a:word)

	if l:found_pos < 0
		return a:text
	endif

	let l:word_length = len(a:word)
	return strpart(a:text, l:found_pos + l:word_length)
endfunction

" match_idを先頭の1単語目の場合と２単語目の場合の大文字のケースで管理する必要が有ることに注意
" 例：{'strlen': 4, 'Strlen': 5}
function! s:add_matches(spell_bad_list, match_id_dict)
	let l:current_matched_list         = keys(a:match_id_dict)
	let l:word_list_for_delete_match   = l:current_matched_list " spellbadとして今回検知されなければ削除するリスト
	let l:match_id_dict                = a:match_id_dict

	for word in a:spell_bad_list
		if index(l:current_matched_list, word) == -1
			" 新しく見つかった場合highlightを設定する
			let l:highlight_group = g:spellunker_spell_bad_group
			if white_list#is_compound_word(word)
				let l:highlight_group = g:spellunker_compound_word_group
			endif

			" 大文字小文字無視オプションを使わない(事故るのを防止するため)
			" ng: xxxAttr -> [atTr]iplePoint
			let l:match_id = matchadd(l:highlight_group, '\v([A-Z]@<!)' . word . '([a-z]@!)\C')
			execute 'let l:match_id_dict.' . word . ' = ' . l:match_id
		else
			" すでにある場合には削除予定リストから単語消す
			let l:del_index = index(l:word_list_for_delete_match, word)
			call remove(l:word_list_for_delete_match, l:del_index)
		endif
	endfor

	return [l:word_list_for_delete_match, l:match_id_dict]
endfunction

function! s:to_first_char_upper(lowercase_spell)
	return toupper(a:lowercase_spell[0]) . a:lowercase_spell[1:-1]
endfunction

function! s:delete_matches(word_list_for_delete, match_id_dict)
	let l:match_id_dict = a:match_id_dict

	for l in a:word_list_for_delete
		let l:delete_match_id = get(l:match_id_dict, l, 0)
		if l:delete_match_id > 0
			try
				call matchdelete(l:delete_match_id)
			catch
				" エラー読み捨て
			finally
				let l:del_index = index(values(l:match_id_dict), l:delete_match_id)
				if l:del_index != 1
					call remove(l:match_id_dict, keys(l:match_id_dict)[l:del_index])
				endif
			endtry
		endif
	endfor

	return l:match_id_dict
endfunction

"cwordの特定位置の文字を置き換えてreplace用文字列を作成
function! s:get_replace_word(cword, target_word, word_start_pos_in_cword, correct_word)
	let l:replace  = strpart(a:cword, 0, a:word_start_pos_in_cword)
	let l:replace .= a:correct_word
	let l:replace .= strpart(a:cword, a:word_start_pos_in_cword + strlen(a:target_word), strlen(a:cword))
	return l:replace
endfunction

" 書き換えてカーソルポジションを直す
function! s:replace_word(target_word, replace_word, is_correct_all)
	let l:pos = getpos(".")
	if a:is_correct_all
		execute "silent! %s/\\v([A-Z]@<!)" . a:target_word . "([a-z]@!)\\C/". a:replace_word . "/g"
	else
		let l:right_move = strlen(a:target_word) - 1
		execute "silent! normal b/" . a:target_word . "\<CR>v" . l:right_move . "lc" . a:replace_word
	endif
	call setpos('.', l:pos)
endfunction

function! s:get_spell_from_correct_list(target_word)
	let l:current_spell_setting = spellunker#get_current_spell_setting()
	setlocal spell

	let l:spell_suggest_list = spellsuggest(a:target_word, g:spellunker_max_suggest_words)

	call spellunker#reduce_spell_setting(l:current_spell_setting)

	if len(l:spell_suggest_list) == 0
		echon "No suggested words."
		return ''
	endif

	let [l:spell_suggest_list_for_input_list, l:spell_suggest_list_for_replace] = s:format_spell_suggest_list(l:spell_suggest_list, a:target_word)

	let l:selected = inputlist(l:spell_suggest_list_for_input_list)
	return  l:spell_suggest_list_for_replace[l:selected - 1]
endfunction

" \n \r \t (制御文字)をスペースに置き換え
function! s:convert_controll_charactor_to_space(line)
	" ex) \nabcd -> \n abcd
	return substitute(a:line, '\v\\(n|r|t)', '  ', "g")
endfunction

" 処理前のspell設定を取得
function! spellunker#get_current_spell_setting()
	redir => spell_setting_capture
		silent execute "setlocal spell?"
	redir END

	" ex) '      spell' -> 'spell'
	return  substitute(l:spell_setting_capture, '\v(\n|\s)\C', '', 'g')
endfunction

" spell設定を戻す
function! spellunker#reduce_spell_setting(spell_setting)
	if a:spell_setting != "spell"
		setlocal nospell
	endif
endfunction

function! s:check(withEchoList)
	" 大文字小文字は区別してリスト登録している

	if &readonly
		return
	endif

	if g:enable_spellunker == 0
		return
	endif

	call white_list#init_white_list()

	let l:window_text_list = getline(1, '$')
	" spellgood で対象から外れる場合もあるので、全部チェックする必要があり
	" TODO: spellgood系操作でmatch_id_dictから消してあげたらチェック不要になる。
	"       ただし、match_id_dictをglobalにする必要あり
	let l:word_list = s:get_word_list(l:window_text_list)

	let l:current_spell_setting = spellunker#get_current_spell_setting()
	setlocal spell

	let l:spell_bad_list = s:filter_spell_bad_list(l:word_list)

	call spellunker#reduce_spell_setting(l:current_spell_setting)

	" ホワイトリスト作るとき用のオプション
	if a:withEchoList
		echo l:spell_bad_list
	endif

	" matchadd()の対象が多すぎるとスクロール時に毎回チェックが走るっぽく、重くなるため
	if len(l:spell_bad_list) > g:spellunker_max_hi_words_each_buf
		if !exists('b:is_too_much_words_notified')
			echon 'Too many spell bad words. (' . len(l:spell_bad_list) . ' words found.)'
		endif

		let l:spell_bad_list = l:spell_bad_list[0:g:spellunker_max_hi_words_each_buf]

		" 2回目は通知しない
		let b:is_too_much_words_notified = 1
	endif

	if !exists('b:match_id_dict')
		let b:match_id_dict = {}
	endif

	let [l:word_list_for_delete_match, b:match_id_dict] = s:add_matches(l:spell_bad_list, b:match_id_dict)

	if len(l:word_list_for_delete_match) == 0
		return
	endif

	let b:match_id_dict = s:delete_matches(l:word_list_for_delete_match, b:match_id_dict)
endfunction

function! s:correct(is_correct_all)
	let l:target_word = s:search_target_word()
	if l:target_word == ''
		return
	endif

	let l:prompt = 'spellunker(' . l:target_word . '->):'
	if a:is_correct_all
		let l:prompt = 'correct-all(' . l:target_word . '->):'
	endif
	let l:input_word = input(l:prompt)

	call s:replace_word(l:target_word, l:input_word, a:is_correct_all)
endfunction

function! s:correct_from_list(is_correct_all)
	let l:target_word = s:search_target_word()
	if l:target_word == ''
		return
	endif

	let l:selected_word = s:get_spell_from_correct_list(l:target_word)
	call s:replace_word(l:target_word, l:selected_word, a:is_correct_all)
endfunction

function! spellunker#execute_with_target_word(command)
	let l:target_word = s:search_target_word()
	if l:target_word == ''
		return
	endif

	execute a:command . ' ' . tolower(l:target_word)
endfunction

function! spellunker#check()
	call s:check(0)
endfunction

function! spellunker#check_and_echo_list()
	call s:check(1)
endfunction

function! spellunker#correct()
	call s:correct(0)
endfunction

function! spellunker#correct_all()
	call s:correct(1)
endfunction

function! spellunker#correct_from_list()
	call s:correct_from_list(0)
endfunction

function! spellunker#correct_all_from_list()
	call s:correct_from_list(1)
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
