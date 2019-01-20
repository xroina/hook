#===============================================================================
# C++ アナライザー
#===============================================================================
package CppAnalyzer;

BEGIN {
	unshift @INC, $0 =~ /^(.*?)[^\/]+$/;
	unshift @INC, readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;
use LexicalAnalyzer;

use base 'LexicalAnalyzer';

# オブジェクト作成
sub new {
	my($this, $params) = @_;
	$this = bless new LexicalAnalyzer($params), $this;
	$this->Analyze;
	return $this;
}

#===============================================================================
# 定数定義
#===============================================================================
# ディレクティブ定義
my $directive = [qw{define undef if ifdef ifndef elif else endif include import using line pragma error warning ident}];
# ディレクティブの正規表現
my $directive_reg = join '|', @$directive;

# キーワード定義
my $keyword = [
#値に関するキーワード
'nullptr',
# 型に関するキーワード
# 基本型
qw{int long short signed unsigned}, qw{float double}, qw{bool true false},
qw{char wchar_t char16_t  char32_t}, qw{void auto},
# 複合型
qw{class struct union enum},
# 型修飾子
qw{const volatile extern register static mutable thread_local},
# 宣言指定子
qw{friend typedef},
# 関数指定子
qw{constexpr explicit inline virtual},
# クラスに関するキーワード
# アクセス制御
qw{public protected private},
# その他
qw{operator this},
# 文に関するキーワード
# 制御構造
qw{if else}, 'for', qw{while do}, qw{switch case default},
qw{break continue goto return }, qw{try catch},
# 式に関するキーワード
# 動的記憶域確保
qw{new delete},
# 型変換
qw{dynamic_cast static_cast const_cast reinterpret_cast},
# 式に関する情報
qw{alignof decltype sizeof typeid},
# 例外処理
qw{throw noexcept},
# 表明
'static_assert',
# テンプレートに関するキーワード
qw{template typename export},
# 名前空間に関するキーワード
'namespace',
# usingディレクティブ
'using',
# インラインアセンブラ
'asm',
# アトリビュート
'alignas',
# 文脈依存のキーワード
qw{final override},
# 代替表現
qw{and and_eq bitand bitor compl not not_eq or or_eq xor xor_eq}
];
# キーワードの正規表現
my $keyword_reg = join '|', @$keyword;

# 代替表現からC表現へのマップ
my $substitution = {'and'=>'&&','and_eq'=>'&=','bitand'=>'&','bitor'=>'|','compl'=>'~',
	'not'=>'!','not_eq'=>'!=','or'=>'||','or_eq'=>'|=','xor'=>'^','xor_eq'=>'^='};

#===============================================================================

# C++アナライザ本体
sub Analyze {
	my($this) = @_;
	$this->debug("Start Analyze");
	for(my $t = $this->{begin}; !$t->eof; $t = parse($t)) {}
	$this->debug("End Analyze");
}

# デバック用プリント
sub debug {
	my($this, @msg) = @_;
	print '[CppAnalyzer] ' . join(',', @msg). "\n" if $this->{debug};
}

sub movenext {
	my($t) = @_;
	my $prev  = $t;
	$t = $t->next('!(space|comment).*');
	$_ = $t->value;
	# classを継承
	$t->{class} = $prev->{class};
	# tokenを継承
	$t->{token} = $prev->{token} unless /^op_([\!\^\-\+\/%=\|\{\(\[\?:;,]|\+\+|\-\-|&&|\|\||<<|>>|.+=)$/;
	$t->{token} = [] unless $t->{token};
	push @{$t->{token}}, $t unless /^(op_[\(\{\[\)\}\;,:]|ident_(private|protected|public))$/;
	return $t;
}

sub parse {
	my($t) = @_;
	my $prev  = $t;
	my $pprev = $t->prev('!(space|comment).*');
	my $token = $prev->{token};

	$t = movenext($t);
	my $next  = $t->next('!(space|comment).*');
#print"#### $t->{file}($t->{line}) ". $t->debug, "\n";
	$_ = $t->value;
	# PH01 ===============================================================================================
	# C++キーワード
	if(/^ident_($keyword_reg)$/) {
		my $req;
		# kindを振り分けます
		$t->kind('keyword');
		$t->kind('statement') if /_(if|else|switch|case|default|for|do|while|continue|break|goto|return|try|catch|throw)$/;
		$t->kind($1)		  if /_(namespace|using|typedef|template)$/;
		$t->kind('class')	  if /_(class|struct|enum|union|typename)$/;
		$t->kind('method')	  if /_(new|delete|sizeof|typeid)$/;
		$t->kind('cast')	  if /_cast$/;
		$t->kind('valiable')  if /_(true|false|nullptr)$/;
		$t->kind('define')	  if /_(int|long|short|float|double|bool|char|.*_t|void|auto|(un)?signed)$/;
		$t->kind('ident')	  if /_(const|this)$/;
		$t->kind('accsess')	  if /_(private|protected|public)$/;
		# 代替表現をC本来のオペレータに変換しちゃいます。
		$t->kind('op'), $t->text($substitution->{$1}) if /_(and|and_eq|bitand|bitor|compl|not|not_eq|or|or_eq|xor|xor_eq)$/;

		# アクセスマーク
		if(/_(private|protected|public)$/) {
			if(grep{$_->kind eq 'class'} @$token) { $req = 'ident_'; }
			elsif(grep{$_ ne $t} @{$t->{token}}) { parse_error($t, "accsess mark"); }
		}
		# 各ステートメントが次に要求するトークン種別を設定します。
		$req = '(ident_|op_[;\{])' if /_namespace$/;				 # }
		$req = '(ident_|op_\{)'	   if /_(class|struct|enum|union)$/; # }
		$req = '(ident_|op_::)'	   if /_using$/;
		$req = '(ident_|op_::)'	   if /_typedef$/;
		$req = 'op_<$'			   if /_template$/;
		$req = 'ident_'			   if /_typename$/;
		$req = '(ident_|op_(::|[;\{]))' if /_(static|extern|inline|virtual|explicit|volatile|friend)$/; # }
		$req = '(ident_|statement_throw|op_(::|[;\{]))' if /_const$/; # }
		$req = 'op_\('			   if /_(if|switch|for|while|catch)$/;
		$req = '(op_\{|ident_)'	   if /_else$/; # }
		$req = 'ident_'			   if /_goto$/;
		$req = '(ident|number|char)_' if /_case$/;
		$req = 'op_:'			   if /_default$/;
		$req = '(op_[&\*;\-\+\(]|(ident|number|string|char)_)' if /_return$/;
		$req = 'op_;'			   if /_(continue|break)$/;
		$req = 'op_\{'			   if /_(do|try)$/;
		$req = '(op_[\;&\*\(]|ident_|number_|string_|char_)' if /_throw$/;
		$req = '(op_\(|ident_)'	   if /_new$/;
		$req = '(op_[\(\[]|ident)' if /_delete$/;
		$req = '(op_\(|ident_)'	   if /_sizeof$/;
		$req = 'op_\('			   if /_typeid$/;
		$req = 'op_<'			   if /_cast$/;
		$req = '(op_[,\(\)\*&>]|ident_.*)$' if /_(int|long|short|float|double|bool|char|.*_t|void|auto|(un)?signed)$/;
		# 各ステートメントが次に要求するトークンと次のトークンが一致しなければエラーにします。
		parse_error($t, "request error", $req) if $req && $next->value !~ /^$req/;

		# 以下のトークンは、tokenが存在するはずがない
		parse_error($t, "bat next token") if /_(return|continue|break|do|try|using|typedef)$/ && grep{$_ ne $t && $_->kind ne 'statement'} @$token;
		# typename はtemplate設定でしか使えない
#		parse_error($t, "bad typename") if /_typename$/   && grep{$_ ne $t && $_->kind ne 'template'} @$token;
		# namesapce は typeが無いか、usingのことしかありえない
		parse_error($t, "bad namespace") if /_namespace$/ && grep{$_ ne $t && $_->kind ne 'using'}    @$token;
	}
	# ディレクティブ
	elsif($_ eq 'op_#' && $next->value =~ /^ident_($directive_reg)$/) {
		$t->text("#$1"); $t->kind('directive');
		$next->delete;
		# TODO プリプロセッサ用処理
		$t = $t->next("space_\n");
		$t->{token} = [];
	}
	# :: オペレータは周りのidentを巻き込んで大きなidentにまとめます
	elsif(/^op_::$/) {
		if($next->kind eq 'ident') {
			$t->text('::' . $next->text);
			$next->delete;
		} else { parse_error($t, "bad :: operator"); }
		$t->kind('ident');
	}
	$_ = $t->value;
	$next  = $t->next('!(space|comment).*');

	# PH02 ===============================================================================================
	# 括弧
	if(/^(op_[\(\{\[])$/) {
		my $last = 'op_)';
		$last = 'op_}' if $_ eq 'op_{';
		$last = 'op_]' if $_ eq 'op_[';
		# class要素の構成
		my $class = $t->{class};
		if(!@$token && $prev->value eq 'op_)') {
			$t->{class} = $pprev->{class};
		} else {
			my $type = 'none';
			my $name = '';
			foreach(@$token) {
				$type = $_->kind if $_->kind =~ /^(namespace|class|method|statement)$/;
				$name = $_->text if $_->kind =~ /^(method|statement)$/;
				$name = $_->text if !$name && $_->kind eq 'define';
			}
			my $newclass = {token=>$token, type=>$type, name=>$name};
			if('ARRAY' eq ref $class) {
				($newclass->{base}) = grep{$_->{type} =~ /^(namespace|class)$/} @$class;
			}
			$t->{class} = [$newclass];
			push @{$t->{class}}, @$class if 'ARRAY' eq ref $class;
		}
#print "token($t->{line}:" .$t->value. "~$last):". join(' ', map{$_->text} @{$t->{class}->[0]->{token}}). "\n" if 'ARRAY' eq ref $t->{class} && 'ARRAY'eq ref $t->{class}->[0]->{token};
		while(!$t->eof && $t->value ne $last) {
			no warnings 'recursion';
			$t = parse($t);
		}
#print "Token($t->{line}:" .$t->value. "):". join(' ', map{$_->text} @{$t->{class}->[0]->{token}}). "\n" if 'ARRAY' eq ref $t->{class} && 'ARRAY'eq ref $t->{class}->[0]->{token};
		$t->{token} = [];
		$t->{class} = $class;
		$t = parse($t);
	}
	# 括弧
	elsif($_ eq 'op_<') {
		my $bk = $t;
#print "<token($t->{line}:" .$t->value."\n";
		while(!$t->eof) {
			no warnings 'recursion';
			$t = parse($t);
			last if $t->value =~ /^op_([^,\*&]||::)/
		}
#print ">token($t->{line}:" .$t->value."\n";
		if($t->value eq 'op_>') {
			$t = parse($t);
		} else {
			$t = $bk;
			$t->{token} = [];
		}
	}
	# identの処理
	elsif(/^ident_/) {
		# identの次が::の場合はオペレータは周りのidentを引き連れて大きなindentにする。
		while($next->value eq 'op_::') {
			last if $next->eof;
			$t->text($t->text . '::');
			$next->delete;
			$next = $next->next('!(space|comment).*');
			if($next->kind eq 'ident') {
				$t->text($t->text . $next->text);
				$next->delete;
				$next = $next->next('!(space|comment).*');
			}
			# 知らなかったが、::* ->* .* なんていうオペレータがあるらしいのでその処理
			elsif($next->value eq 'op_*') {
				my $n = $next->next('!(space|comment).*');
				if($n->kind eq 'ident') {
					$t->text($t->text . '*' . $next->text);
					$next->delete;
					$n->delete;
					$next = $n->next('!(space|comment).*');
				}
			}
		}
		# namespace|class|usingに続くidentはなにかの宣言なのでdefineに変える
		if(grep{$t ne $_ && $_->kind =~ /^(namespace|class|using)$/} @$token) {
			$t->kind('define');
		}
		# identが２つ続いていたら、最初のidentは宣言だ。
		$prev->kind('define') if $prev->kind eq 'ident';
		
		$t->kind('valiable') if $prev->kind eq 'define' && $next->value eq 'op_[';

		if($t->kind eq 'ident') {
			# カッコの始まりならメソッドだと思われます。
			if($next->value eq 'op_(') {
				$t->kind('method');
				# ただし、methodに所属している場合の、define,method,(の順は、クラスのインスタンス化なのでvaliableです。
				if($prev->kind eq 'define' && 'ARRAY' eq $t->{class} && $t->{class}->[0]->{type} eq 'method') {
					$t->kind('valiable');
				}
			}
			# 構文の終わりっぽいところだったら変数だと思われます。
			$t->kind('valiable') if $next->value =~ /^op_([\!\^\-\+\/%=\|\?;,\)]|\+\+|\-\-|&&|\|\||<<|>>|.+=)$/;

			# : の場合は、ラベルだったりすることがあるので、更にその前を見て判断します
			if($next->value eq 'op_:') {
				if($prev->value =~ /^(op_\?|statement_case)$/) {
					$t->kind('valiable');
				} else {
					$t->kind('label');
				}
			}
		}
		$_ = $t->value;
	}
	# 宣言の前がidentならそのidentは宣言だ
	elsif(/^define_/ && $prev->kind eq 'ident') {
		$prev->kind('define');
	}
	# ポインタと参照
	elsif(/^op_[&\*]$/) {
		if($prev->kind eq 'ident') {
			# 直前がidentで、その前が宣言か文の終わりっぽいものなら、直前のidentは宣言だ
			if($pprev->value =~ /^(define_.*|op_[\{\};:,]|)$/){
				$prev->kind('define');
			}
			if($pprev->value =~ /^(op_[\(\{;:,]|keyword_.*)$/ && $next->kind eq 'ident'){
				$prev->kind('define');
			}
			# 直前がidentで、その前が演算子なら直前のidentは変数だ
			elsif($pprev->value =~ /^(op_[\(\)\+\-\*\/%\|&])$/) {
				$prev->kind('valiable');
			}
		}
		# 直前が宣言なら、ポインタも宣言にしちゃえ
		$t->kind('define') if $prev->kind eq 'define';
	}
	# アロー演算子の前がidentならそれは変数だ
	elsif(/^op_(->|\.)$/) {
		if($prev->kind eq 'ident') {
			$prev->kind('valiable');
		}
	}
	# PH3==========================================================
	if($prev->kind eq 'valiable' && $pprev->kind eq 'define' && 'ARRAY' eq ref $t->{class}) {
#print "+++++ ". $prev->value. "\n";
		my $p;
		for($p = $pprev; !$p->bof; $p = $p->prev('!(space|comment).*')) {
			last unless $p->kind eq 'define';
		}
		unless($p->value eq 'keyword_static') {
			$t->{class}->[0]->{valiable} = [] unless $t->{class}->[0]->{valiable};
			push @{$t->{class}->[0]->{valiable}}, $prev;
		}
	} elsif($prev->kind eq 'method' && 'ARRAY' eq ref $t->{class}) {
		$t->{class}->[0]->{method} = [] unless $t->{class}->[0]->{method};
		push @{$t->{class}->[0]->{method}}, $prev;
	}

	return $t;
}

sub parse_error {
	my($t, @msg) = @_;
	my $prev = $t->prev('!(space|comment).*');
	my $next = $t->next('!(space|comment).*');

	print "parse error:" . caller(0) . "\n";
	print "$t->{file} ($t->{line})\n";
	print "token=".$t->{token}. "\n";
	print "prev=". $prev->value. "\n";
	print "this=". $t->value. "\n";
	print "next=". $next->value. "\n";
	print join(' ', map{print join(",", each %$_)."\n"; $_->text} @{$t->{token}}). "\n";
	print join("\n", @msg). "\n";

	die;
}

1;
