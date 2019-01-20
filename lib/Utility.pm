#===============================================================================
# ユーティリティ
#===============================================================================
package Utility;

use strict;
use warnings;
use utf8;
use Encode;

# 前後のスペースを取り除き、'#'以降をコメントとして取り除いた文字を取得する。
sub getLine {
	my ($str) = @_;
	chomp $str;
	$str =~ s/#.*$//;
	$str =~ s/^\s*(.*?)\s*$/$1/;
	return $str;
}

# コマンドライン引数の正規表現取得
my $optionRegexp = sub {
	my($str) = @_;
	return '--?'. substr($str, 0, 1) . '(?:'. quotemeta(substr($str, 1)) . ')?';
};

# コマンドラインオプションの解析
sub getStartOption {
	my($param, $options, $path) = @_;
	my $file = [];

	$path = 'path' unless $path;
	$param = {} unless $param;
	$param->{$path} = [] unless 'ARRAY' eq ref $param->{$path};

	# オプション文字列の解析
	my $regex = [];
	foreach(@$options) {
		$_ = getLine($_);
		next unless $_;

		my $obj = {name=>$_, type=>'bool', regex=>''};
		if(/^(.*?)\s*=\s*(.*)$/) {
			($obj->{name}, $obj->{type}) = ($1, $2);
			$obj->{regex} = &$optionRegexp($obj->{name}) . '[=:]?';
			if($obj->{type} eq '#' || $obj->{type} =~ /^I(Int(eger)?)?$/i ) {
				$obj->{regex} .= '(\\d+)?';
				$obj->{type} = 'int';
			}
			elsif($obj->{type} eq '*' || $obj->{type} =~ /^S(tr(ing)?)?$/i) {
				$obj->{regex} .= '(.+)?';
				$obj->{type} = 'string'
			}
			elsif($obj->{type} eq '@' || $obj->{type} =~ /^A(rray)?$/i) {
				$obj->{regex} .= '(.+)?';
				$obj->{type} = 'array'
			}
			elsif($obj->{type} eq '&' || $obj->{type} =~ /^F(ile)?/i) {
				$obj->{regex} .= '(.+)?';
				$obj->{type} = 'file';
			}
		} else {
			$obj->{regex} = &$optionRegexp($_);
		}
		push @$regex, $obj;
	}

	# コマンドライン引数取得本体
	foreach my $arg(@ARGV) {
		my $flag;
		foreach my $reg(@$regex) {
			my($n, $r, $t) = (lc $reg->{name}, "^$reg->{regex}\$", $reg->{type});
			my $f = "$n\_flag";
			if($arg =~ /$r/i) {
				if($t eq 'bool') {
					$param->{$n} = 0 unless exists $param->{$n};
					$param->{$n} = !$param->{$n};
				}
				elsif($1) {
					my $str = Encode::decode('utf8', $1);
					if($t eq 'int') { $param->{$n} = $str + 0; }
					elsif($t eq 'array') {
						$param->{$n} = [] if 'ARRAY' eq ref $param->{$n};
						push @{$param->{$n}}, $str;
					}
					elsif($t eq 'file') { push @$file, $str; }
					else { $param->{$n} = $str; }
				}
				else { $param->{$f} = 1; }
				$flag = 1;
			}
			elsif($param->{$f}) {
				my $str = Encode::decode('utf8', $arg);
				if($t eq 'int') { $param->{$n} = $str + 0; }
				elsif($t eq 'array') {
					$param->{$n} = [] if 'ARRAY' eq ref $param->{$n};
					push @{$param->{$n}}, $str;
				}
				elsif($t eq 'file') { push @$file, $str; }
				else { $param->{$n} = $str; }
				delete $param->{$f};
				$flag = 1;
			}
		}
		push @{$param->{$path}}, Encode::decode('utf8', $arg) unless $flag;
	}
	# オプションがファイルを読むことになっていたらファイルを読む
	foreach my $f(@$file) {
		use FileHandle;
		my $fh = new FileHandle($f) or die "$f file open error:$!";
		$fh->binmode(':utf8');
		while(<$fh>) {
			$_ = getLine($_);
			next unless $_;

			if(/^(\w+)\s*=\s*(.*)$/) {
				$param->{lc $1} = $2;
			} else {
				push(@{$param->{$path}}, split ' ', $_);
			}
		}
		$fh->close;
	}
}

# js,css,imgのシンボリックリンクを作成する。
sub createSymLink {
	my($prog) = $0 =~ /^(.*?)[^\/]+$/;
	($prog) = readlink($0) =~ /^(.*?)([^\/]+)$/ if -l $0;
	foreach('js', 'css', 'img') {
		if(-d "$prog/$_") {
			unlink $_ if -d $_;
			symlink "$prog/$_", $_;
		}
	}
}

# HTMLに出力不能な文字を&xx;形式に変換する。
sub toHtml {
	($_) = @_;
	s/&/&amp;/gm;
	s/</&lt;/gm;
	s/>/&gt;/gm;
	s/"/&quot;/gm;
	s/\t/    /gm;
	s/\n/<br>\n/gm;
	s/ /&nbsp;/gm;
	
	return $_;
}

# パスのリストがフォルダかファイルかを判定し、フォルダ(または*付きの文字)ならその先を再帰的にファイル取得する。
sub getRecursivePath {
	my($in, $ext) = @_;
	my $ary = [];
    foreach(@$in) {
        if(-d) {
	        s#/$##;
	        no warnings 'recursion';
	        push @$ary, @{getRecursivePath([glob "$_/*"], $ext)};
        }
        elsif(-f) {
	        next if defined $ext && !/\.($ext)$/;
	        unless(m#^/#) {
		        use Cwd 'getcwd';
		        $_ = getcwd() . "/$_";
	        }
	        s#/(\.?/)+#/#mg;
	        s#[^/]+/\.\./##mg;
	        push @$ary, $_;
        }
        elsif(/\*/) {
	        no warnings 'recursion';
	        push @$ary, @{getRecursivePath([glob], $ext)};
        }
    }
	return $ary;
}

# エンコード自動変更(UTF-8)
sub toUTF8 {
	my($str) = @_;
	use Encode::Guess qw/sjis euc-jp 7bit-jis/;
	my $decoder = Encode::Guess->guess($str);
	die "Encode::Guess Fail:decoder=$decoder:error=$!\n" unless ref $decoder;
	return $decoder->decode($str);
}

1;
