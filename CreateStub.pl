#!/usr/bin/perl

BEGIN {
    unshift @INC, map "$_/lib", $0 =~ /^(.*?)[^\/]+$/;
    unshift @INC, map "$_/lib", readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;

use XML::Simple;

use Utility;

use FileHandle;

use LexicalAnalyzer;

binmode STDIN , ':utf8';
binmode STDOUT, ':utf8';

my($progpath, $prog) = $0 =~ /^(.*?)([^\/]+)$/;
my $command_line = "$prog " . join ' ', @ARGV;

my $param = {};
Utility::getStartOption($param, ['name=*', 'debug', 'help']);

my $class_name = $param->{name};

$param->{help} = 1 unless $class_name;

if($param->{help}) {
#-------------------------------------------------------------------------------
# ヘルプ表示
#-------------------------------------------------------------------------------
    print <<"USAGE";
usage $prog [OPTION] [library path]...

リストにしたがって、スタブをつくります。

OPTION:
  -n, -name [NAME]          スタブの名前を指定します。
  -d, -debug                デバック時に出すメッセージを詳細にします。
                            ただしコンパイルエラーの元が増えます。
  -h, -help                 このヘルプを表示します。
NOTE:
  工事中

USAGE
    exit 0;
}
#-------------------------------------------------------------------------------

print <<"EOF";
#===============================================================================
# Start:$command_line
#===============================================================================
EOF

# 現在時刻取得
my ($sec, $min, $hour, $day, $mon, $year) = localtime(time);
my $now = sprintf '%04d/%02d/%02d-%02d:%02d:%02d',
                $year + 1900, $mon + 1, $day, $hour, $min, $sec;

# クラス名とヘッダdefineの生成
$class_name = "CC_STUB" unless $class_name;
$class_name =~ s/\..*$//;
my $hedder_define = "__HOOK_". uc($class_name). "_H__";

# テンポラリファイル
my $tmp = $now;
$tmp =~ tr#-:/##d;
$tmp = "/tmp/CreateSTUB_$tmp.tmp";
system "rm /tmp/CreateSTUB_*.tmp";

print "    [一時ファイル]$tmp\n";

# 設定ファイル
my $conf = "${class_name}.lst";
my $confxml = "${class_name}.xml";

if(-e $confxml) {
    # Xml::Simpleのインスタンス生成
    my $xml = XML::Simple->new;
    # xmlを読み込ませる
    my $data = $xml->XMLin($confxml);
    
    print "$data->{stub}->[0]->{header}\n";
    print "$data->{stub}->[0]->{main}\n";
    print "$data->{stub}->[0]->{include}\n";
    
    exit 1;
}

# 出力ファイル
my $outh = "${class_name}.h";
my $outc = "${class_name}.cpp";

rename $outh, "$outh~" if -e $outh;
rename $outc, "$outc~" if -e $outc;

print "    [input]$conf\n";
print "    [output]$outh\n";
print "    [output]$outc\n";

# パス設定
push @{$param->{inc}}, $ENV{BASE_ENV}, "$ENV{IIR_ROOT_G}/develop";

my $library = [];
if(exists $param->{path}) {
    foreach(@{$param->{path}}) {
        if(-d $_) {
            s/\/$//;
            push @$library, "$_/*.so";
        } elsif(-e $_) {
            push @$library, $_;
        }
    }
}

my $ld_preload = [];
if(exists $ENV{LD_PRELOAD}) {
    foreach(split ' ', $ENV{LD_PRELOAD}) {
        next unless -e $_;
        push @$ld_preload, $_;
    }
}

my $ld_library = [];
if(exists $ENV{LD_LIBRARY_PATH}) {
    foreach(split ':', $ENV{LD_LIBRARY_PATH}) {
        next unless -d $_;
        push @$ld_library, "$_/*.so";
    }
}

my $ld_config = [];
my $ldconfig = "ldconfig -p 2> /dev/null";
print("  [command]$ldconfig\n");

foreach(`$ldconfig`) {
    chomp;
#    print "    [ldconfig]$_\n";
    next unless s/^.*?\s+=>\s+//;
    push @$ld_config, $_;
}

print "    [指定したライブラリ]$_\n"  foreach @$library;
print "    [LD_PRELOAD]$_\n"      foreach @$ld_preload;
#print "    [ldconfig]$_\n"        foreach @$ld_config;
print "    [LD_LIBRARY_PATH]$_\n" foreach @$ld_library;
print "    [include path]$_\n"    foreach @{$param->{inc}};

my $stub = {};

print <<"EOF";
#-------------------------------------------------------------------------------
# 設定ファイル($conf)から情報をとりだし、ヘッダを解析する
#-------------------------------------------------------------------------------
EOF

if(-e $confxml) {
} else {
    my $fd = new FileHandle($conf, 'r') or die "$conf file open error:$!\n";
    binmode $fd, ':utf8';
    my $l = 0;
    while(<$fd>) {
        chomp;
        $l++;
        print "    [line$l]$_\n";
        s/#.+$//;
        
        if(my($file, $method, $result) = /^\s*([\w]+\.h)\s+([\w:<>\*]+)\s+(.+?)\s*$/) {
            my($class, $func) = $method =~ /^([\w:<>\*]*?)(?:::)?([\w<>\*]+)$/;

            print "        -> file=$file class=$class function=$func result=$result\n";
            die(  "        -> 関数名が定義されていません\n") unless $func;

            find_define($file, $class, $func, $result);
        } else {
            print "        -> 対象外の行\n";
        }
    }
    $fd->close();
}

print <<"EOF";
#-------------------------------------------------------------------------------
# 不必要になった情報を削除する
#-------------------------------------------------------------------------------
EOF
#while(my($class, $s) = each %$stub) {
#    my $flag;
#    while(my($func, $f) = each %{$s->{func}}) {
#        $flag = 1, next if exists $f->{hedder};
#        print "        [delete]${class}::$func\n";
#        delete $s->{func}->{$func};
#    }
#    print("    [delete]$class\n"), delete $stub->{$class} unless $flag;
#}

print <<"EOF";
#-------------------------------------------------------------------------------
# nmコマンドで.soからシンボル情報を検索する
#-------------------------------------------------------------------------------
EOF

my $grep_regexp = [];
while(my($class, $s) = each %$stub) {
    my $class_regexp = "";
    $class_regexp .= join ".*?", split /::|<.*>/, $class;
    foreach my $func(keys %{$s->{func}}) {
        my $func_regexp = "";
        $func_regexp .= ".*?$_" foreach split /::|<.*>/, $func;
        push @$grep_regexp, $class_regexp. $func_regexp;
    }
    
}
my $grep = " [TW] (". join('|', @$grep_regexp). ")";

my $awk = <<'EOF';
-F '[ :]' '{ fd = system("echo -n \""$1" "$4" \"; c++filt -i "$4); }'
EOF
$awk =~ tr/\012\015/ /;

my $sofiles = {};
foreach(map{glob} @$library, @$ld_preload, @$ld_config, @$ld_library) {
    next if exists $sofiles->{$_};
    my $nm = "nm -o $_ 2> /dev/null | egrep '$grep' | awk $awk >> $tmp";
    print("  [command]$nm\n");
    system $nm;
    $sofiles->{$_} = "cmplete";
}

#my $nm = "nm -o\n";
#$nm .= "$_\n" foreach @$library;
#$nm .= "$_\n" foreach @$ld_preload;
#$nm .= "$_\n" foreach @$ld_config;
#$nm .= "$_\n" foreach @$ld_library;
#$nm .= "2> /dev/null\n";
#$nm .= "| awk $awk > $tmp";
#
#print("  [command]$nm\n");
#$nm =~ tr/\012\015/ /;
#system $nm;

print <<"EOF";
#-------------------------------------------------------------------------------
# nmの結果をgrepして対象のメソッドを抽出する
#-------------------------------------------------------------------------------
EOF
while(my($class, $s) = each %$stub) {
    foreach my $func(keys %{$s->{func}}) {
        my $f = $s->{func}->{$func};

        my $method = "${class}::$func";
        $method = $func unless $class;

print <<"EOF";
#-------------------------------------------------------------------------------
# 対象メソッド($method)のデマングル情報から、メソッド引数と戻り値を解析する
#-------------------------------------------------------------------------------
EOF
        # grepコマンドのコマンドライン
        $grep = "grep '$method' $tmp";
        print("         [command]$grep\n");

        foreach(`$grep`) {
            chomp;
            print "            [検索結果]$_\n";

            my($so, $name, $demangle) = /^(.*?) (.*?) (.*)$/;
            
            print "                -> $demangle\n";
            print "                vs $method\n";
            
            my $regex = $method;
            $regex =~ s/>$//g;
            next unless $demangle =~ /\b$regex\b/;

            # 入力された関数名と一致したらレキシュアルアナライザにかける
            print "                    [解析開始]$demangle\n";
            my $lex = new LexicalAnalyzer({code=>$demangle, debug=>0});
            print "                    [解析結果]". $lex->tokens. "\n";

            next if(exists $f->{nm}->{$name});

            $f->{nm}->{$name} = {so=>$so, lex=>$lex, method=>$demangle};

            print "                        ->採用\n";
        }

        print "            [最終結果]";
        my $flag = 0;
        while(my($name, $hash) = each %{$f->{nm}}) {
            $flag = 1;
            print $hash->{lex}->string. "\n";
            print "                -> $hash->{so} : $name\n";
        }
        print "見つかりませんでした。\n" unless $flag;
    }
}
#unlink $tmp;

print <<"EOF";
#-------------------------------------------------------------------------------
# フックおよびスタブのコードを生成する
#-------------------------------------------------------------------------------
EOF

# ヘッダ部分のソース構成
my $head = <<"EOF";
/*!
 * \@file "$outh"
 *
 * \@brief このソースは $prog スクリプトで自動生成されました。
 *
 * \@par 備考
 * \@details
 *    - command_line:$command_line
 *    - created:$now
 */

#ifndef $hedder_define
#define $hedder_define

//---- ヘッダファイルインクルード
#include "AC_STUB.h"
EOF

my $define = <<"EOF";

//---- 名前空間定義
/*!
 * \@namespace   HOOK
 * \@brief       $prog が構成する標準のネームスペースです。
 */
namespace HOOK
{
EOF

# 本体部分のソース構成
my $include = <<"EOF";
/*!
 * \@file "$outc"
 *
 * \@brief このソースは $prog スクリプトで自動生成されました。
 *
 * \@par 備考
 * \@details
 *    - command_line:$command_line
 *    - created:$now
 */

//---- ヘッダファイルインクルード
#include <iostream>
#include "$outh"
EOF

my $static = <<"EOF";

using std::cout;
using std::endl;

//---- 名前空間定義
/*!
 * \@namespace   HOOK
 * \@brief       $prog が構成する標準のネームスペースです。
 */
namespace HOOK
{
EOF

my $code = '';

while(my($class, $s) = each %$stub) {
    next unless 'HASH' eq ref $s;
    next unless $s->{file};

    $head .= "#include \"$s->{file}\"\n";

    while(my($func, $f) = each %{$s->{func}}) {
        my $method = "${class}::$func";
        $method = $func unless $class;
    
        my $ignition = "CC_$method";
        $ignition =~ s/(::|<|>)/_/g;
        $ignition =~ s/_+/_/g;
        $ignition =~ s/_$//g;

        print <<"EOF";
#-------------------------------------------------------------------------------
# メソッド(${method})のフック情報をクラス(${ignition})として作成する。
#-------------------------------------------------------------------------------
EOF

        $define .= <<"EOF";
/*!
 * \@class   ${ignition}
 *          $outh
 *          “inc/$outh”
 *
 * \@b       クラス論理名
 *          ${method}用
 *          フック情報クラス
 *
 * \@brief   元の関数をフックするために必要な情報を定義する。
 *
 * \@par     概要説明
 * \@details
 *        - HOOK::AC_STUB クラスを継承する。
 *        - 構築子と消滅子を定義する。
 *        - 関数をフックするための関数とライブラリの紐付けリストを定義する。
 *
 * \@par     備考
 *          なし
 */
class ${ignition} :
    public AC_STUB {
public:
    // フックオブジェクト
    static ${ignition} hook;

EOF

        my $names = [];

        #-----------------------------------------------------------------------
        # デマングルした結果またはヘッダから実体を呼び出す引数を構成する
        #-----------------------------------------------------------------------
        my $i = 0;
        while(my($ln, $nm) = each %{$f->{nm}}) {
            print "        [シンボル情報]$nm->{so} $ln -> $nm->{method}\n";

            $i++;
            push @$names, {func=>$ln, so=>$nm->{so}};

            my $arg = [];   # 引数の配列
            
            print "        [シンボル]". $nm->{lex}->string. "\n";
            print "        [ヘッダ　]". $f->{hedder}->string. "\n";

            # デマングルした結果から引数の箇所を抽出する
            my $begin = $nm->{lex}->begin()->next('op_\(');

            my $hed;        # ヘッダ抽出フラグ
            if($begin->eof) {
                # デマングルした結果に引数情報がない場合はヘッダから抽出する
                print "            -> ライブラリのシンボル情報に引数と戻り値の情報がありません。\n";
                print "               このため、ヘッダ情報から引数と戻り値を推測します。\n";
                $begin = $f->{hedder}->begin->next('op_\(');
                $hed = 1;   # ヘッダ抽出フラグON
            }
            if($begin->eof) {
                print "            -> シンボル情報とヘッダ情報から引数と戻り値が特定できませんでした。\n";
            }
            my $end = $begin->next('op_\)');

            print '        [解析した引数情報]'. new TokenAnalyzer()->string($begin, $end) . "\n";

            # 引数の抽出本体
            my $count = 0;  # テンプレートカウンタ
            my $token = new TokenAnalyzer();
            for(my $t = $begin->next; !$t->eof($end); $t = $t->next) {

                # コメントとスペースは飛ばす
                next if $t->kind =~ /^(comment|space)$/;

                # テンプレートの処理
                $count++ if $t->value =~ /^op_<$/;
                $count-- if $t->value =~/^op_>$/;

                if($count || $t->value !~ /^op_[,\)]$/) {
                    $token->append($t);
                } else {
                    next if $token->string =~ /^\s*$/;

                    my $no = 1 + @$arg;
                    $token->{param} = "p$no";

                    # ヘッダから抽出した場合は、引数のパラメータ名を取り除く
                    if($hed) {
                        my $p;
                        for($p = $token->begin; !$p->next->eof; $p = $p->next) {
                            last if $p->value eq 'op_=';
                        }
                        while(!$p->next->eof) {
                            $p->delete;
                        }
                        $p->delete;
                    }

                    push @$arg, $token; # 引数の配列にトークンを加える

                    print "            [引数情報$no]". $token->string. " -> $token->{param}\n";

                    $token = new TokenAnalyzer();
                }
            }
            my $after = new TokenAnalyzer();
            while(!$end->next->eof) {
                $end = $end->next;
                
                next if $end->kind =~ /^(comment|space)$/;
                $after->append($end);
            }
            $after = $after->string;

            # 関数の戻り値の抽出
            my $def = new TokenAnalyzer();
            my $ret = new TokenAnalyzer();
            print '            [戻り値とその型]';
            my $this = $class;
            for(my $t = $f->{hedder}->begin;
                !$t->eof($f->{hedder}->{this}->prev); $t = $t->next) {

                # コメントとスペースは飛ばす
                next if $t->kind =~ /^(comment|space)$/;

                print $t->value. ' ';

                $this = 0, next if $t->value =~ /^ident_static$/;

                $count-- if $t->value =~ /^op_>$/;

                unless($count) {
                    $ret->append($t) if $t->text !~ /^(const|template|[<>])$/;
                    $def->append($t) if $t->text !~ /^(template|[<>])$/;
                }

                $count++ if $t->value =~ /^op_<$/;
            }
            $ret = $ret->string;
            $def = $def->string;

            print "戻り値=$ret 型=$def\n";

            my $type = "F$i";

            # 引数の構成
            my $args = "\n". join ",\n", map{"        ". $_->string. " $_->{param}"} @$arg;
            $_ = $args;
            s/\s+/ /g;
            print "            [引数文字列]$_\n";

            # staticでもC形式でもない場合はthisをパラメータの先頭に足す
            if($this) {
                $token = new TokenAnalyzer();
                $token->append(new Token('const void*', 'ident'));
                $token->{param} = 'this';
                unshift @$arg, $token;
            }

            # 関数オブジェクトのtypedef定義
            my $typedef = join ",\n", map{"        ". $_->string} @$arg;
            $typedef = "$ret (*$type)(\n$typedef)";
            $_ = $typedef;
            s/\s+/ /g;
            print "            [typedef]$_\n";

            $define .= "    //! 関数ポインタの別名定義\n";
            $define .= "    typedef $typedef;\n";

            # デバック用標準出力文字の構成
            my $debug_args = '';
            my $debug_return = '';
            if($param->{debug}) {
                $debug_args = '<< " parameters:" ';
                foreach(@$arg) {
                    $debug_args .= "<< \" $_->{param}=\" << $_->{param}\n";
                }
                $debug_return = '<< " -> return:" << ret';
            }
            
            # リターン用変数などの定義
            my $return_variable = '';
            my $return = "return";
            unless($ret eq 'void') {
                $return_variable = "$ret ret = ";
                $return = "return ret";
            }

            # オリジナルの関数呼び出しパラメータ
            my $orignal_param = join(', ', map{$_->{param}} @$arg);

            my $object = "::HOOK::${ignition}::hook";

            $code .= <<"EOF";
/*!
 * \@b       メンバ関数名
 *          オリジナルメソッド($method)の上書き
 *
 * \@brief   メソッド($method)をフックする。
 *
 * \@par     機能説明
 * \@details
 *        - メソッド($method)をフックする。
 *        - 条件に一致した場合に、オリジナルと別の動きをさせる。
 *        - 条件に一致しない場合はオリジナルメソッドを呼ぶ。
 *
 * \@param   元の引数と同じ
 * \@return  元の引数と同じ
 *
 * \@par     備考
 *          なし
 */
$def $method($args)$after
{
    // debugが有効なら、関数開始メッセージを表示する。
    if(::HOOK::AC_STUB::debug)
    {
        cout << "[HOOK START]$method()"
            << " execute:"  << $object.execute
            << " ignition:" << $object.ignition
            << " count:"    << $object.count
            $debug_args    << endl;
    }

    // 条件と一致したら、オリジナルとは別の動きをする。
    if($object.execute &&
        $object.ignition ==
        ++$object.count)
    {
        cout << "[Ignition]" << endl;
        $f->{result}
    }

    // オリジナルメソッドを呼ぶ
    typedef const ::HOOK::${ignition}::
        $type F;
    F org = (F)$object.
            getFunc("$ln");
    $return_variable(*org)($orignal_param);

    // debugが有効なら、関数終了メッセージを表示する。
    if(::HOOK::AC_STUB::debug)
    {
        cout << "[HOOK END]$method()"
            $debug_return    << endl;
    }
    $return;
}

EOF
        }   # end while(my($ln, $nm) = each %{$f->{nm}})

        my $func_list = '';
        foreach(@$names) {
            $func_list .= "T_so_func_pair(\"$_->{so}\",\n    \"$_->{func}\"),\n";
        }

        $define .= <<"EOF";

    // コンストラクタ
    ${ignition}();

    // デストラクタ
    virtual ~${ignition}();

};  // end class ${ignition}

EOF

        $static .= <<"EOF";

//! フックオブジェクト実体
${ignition}
${ignition}::hook;

/*!
 * \@b       メンバ関数名
 *          構築子
 *
 * \@brief   クラス生成に伴う初期化処理。
 *
 * \@par     機能説明
 * \@details
 *        - 関数とライブラリの紐付けリストをパラメータとして継承元クラスの構築子を呼ぶ。
 *
 * \@param   なし
 * \@return  なし
 *
 * \@par     備考
 *          なし
 */
${ignition}::
${ignition}() :
    AC_STUB({
$func_list}) {
    return;
};

/*!
 * \@b       メンバ関数名
 *          消滅子
 *
 * \@brief   クラス消滅に伴う終了処理。
 *
 * \@par     機能説明
 * \@details
 *        - 処理なし。
 *
 * \@param   なし
 * \@return  なし
 *
 * \@par     備考
 *          なし
 */
${ignition}::
~${ignition}() {
    return;
};

EOF
    }
}

print <<"EOF";
#-------------------------------------------------------------------------------
# フックおよびスタブのコードをファイルに出力する
#-------------------------------------------------------------------------------
EOF

my $fh = new FileHandle($outh, 'w') or die "$outh file open error:$!\n";
binmode $fh, ':utf8';
$fh->print($head);
$fh->print($define);
$fh->print(<<"EOF");

}   // end namespace HOOK

#endif // $hedder_define
EOF
$fh->close();

my $fc = new FileHandle($outc, 'w') or die "$outc file open error:$!\n";
binmode $fc, ':utf8';
$fc->print($include);
$fc->print($static);
$fc->print(<<"EOF");

}   // end namespace HOOK

EOF
$fc->print($code);
$fc->close();

print <<"EOF";
#-------------------------------------------------------------------------------
# できたヘッダファイル($outh)を標準出力する。
#-------------------------------------------------------------------------------
EOF

system "cat $outh";

print <<"EOF";
#-------------------------------------------------------------------------------
# できたソースコード($outc)を標準出力する。
#-------------------------------------------------------------------------------
EOF

system "cat $outc";

exit 0;

#-------------------------------------------------------------------------------
# メソッド定義を検索する
#-------------------------------------------------------------------------------
sub find_define {
    my($file, $class, $func, $result) = @_;
    print "        [Find]method:${class}::$func\n";

    $stub->{$class} = {func=>{}} unless exists $stub->{$class};
    my $s = $stub->{$class};
    
    $s->{func}->{$func} = {result=>$result} unless exists $s->{func}->{$func};
    my $f = $s->{func}->{$func};

    # ファイル検索
    my $find = "find\n".
        join('', map{"$_/\n"} @{$param->{inc}}).
<<"EOF";
-name $file
| grep -v ".svn"
| grep -v ".org"
| grep -v ".old"
| grep -v ".bak"
| grep -iv test
| grep -iv stub
| grep -iv tool
EOF

#    print "          [command]$find\n";
    $find =~ tr/\012\015/ /;

    foreach(`$find`) {
        chomp;
        print "                -> 検索結果:$_\n";
        $s->{path} = $_;
        $s->{file} = [reverse split '/']->[0];
    }
    print("                -> 検索失敗\n"), return 0 unless exists $s->{path};

    # レキシカルアナライザ作成
    print "            [解析開始]$s->{path} ${class}::$func\n";
    unless(exists $s->{lex}) {
        my $prm = {file=>$s->{path}, debug=>0};
        $s->{lex} = new LexicalAnalyzer($prm);
    }

    # メソッドの検索
    my $lex = $s->{lex};
    $func =~ s/<.*>//;
    foreach(@{$lex->find_define($func)}) {
        print "            [対象トークン抽出]". $_->tokens. "\n";
        $f->{hedder} = $_;

        # 検索できた場合は終了
        print "                -> 対象トークン抽出成功:". $_->string. "\n";
        return 1;
    }

    # 継承クラス検索
    print "             -> 検索失敗:継承元クラスの検索を試みます。\n";
    $class =~ s/<.*>//;
    foreach(@{$lex->find_define($class, 'class')}) {
        my $end = $_->end;
        for(my $t = $_->{this}->next; !$t->eof; $t = $t->next) {
            $_ = $t->value;
            next if /^(space|comment)/;
            next if /^op_[,:]/;
            last if /^op/;
            next if /^ident_(public|protected|private)$/;

            $_ = $t->text;
            print "            [継承元クラス抽出] $class -> $_\n";

            my $file = [reverse split '::']->[0] . ".h";
            return 1 if find_define($file, $_, $func, $result);
        }
    }
    print "             -> 検索失敗:継承元クラスもみつかりません。\n";

    return 0;
}

