#===============================================================================
# レキシカルアナライザ
#===============================================================================
package LexicalAnalyzer;

BEGIN {
	unshift @INC, $0 =~ /^(.*?)[^\/]+$/;
	unshift @INC, readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;
use TokenAnalyzer;

use base 'TokenAnalyzer';

#-------------------------------------------------------------------------------
# オブジェクト作成
#-------------------------------------------------------------------------------
sub new {
	my($this, $params) = @_;
	$this = bless new TokenAnalyzer($params), $this;
	if($this->{file} && !$this->{readfile}) {
		use FileHandle;
		$this->debug("Read:$this->{file}");

		my $fh = new FileHandle($this->{file}, 'r') or die "$this->{file} file open error:$!\n";
		$fh->binmode;
		my $code = join '', <$fh>;
		$fh->close;

		use Utility;
		$this->{code} = Utility::toUTF8($code);;
		$this->{readfile} = 1;
	}
	$this->Analyze;

#$this->debug("KIND:".$this->{end}->kind);
#$this->debug("begin:$this->{begin},prv:$this->{begin}->prev,nxt:$this->{begin}->next");
#for(my $t = $this->begin; !$t->eof; $t = $t->next) {
#	$this->debug("$t:$t->kind:$t->text ");
#}
#$this->debug("end:$this->{end},prv:$this->{end}->prev,nxt:$this->{end}->next");
#exit;

	delete $this->{code};

	return $this;
}

#-------------------------------------------------------------------------------
# レキシカルアナライザ本体
#-------------------------------------------------------------------------------
sub Analyze {
	my($this) = @_;
	return unless $this->{code};
	$this->debug("Start Analyze");

	my $qu = {string=>'"', char=>"'"};
	my $op = [
		quotemeta '!#$%&()*+,-./:;"\'<=>?@[\]^`{|}　、。・，．（）「」｛｝【】『』〔〕［］〈〉《》☆★※○●◎◇◆□■▽△▼▲①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳',
		[qw{== != <= >= << >> += -= *= /= %= |= &= ^= ++ -- -> => =< :: || &&},'/*','*/','//','##',"\\\n"],
		[qw{<<= >>= === !==}]
	];

	my $t = new Token();
	my $state;
	my $code = [split //, $this->{code}]; push @$code, ('','','');
	for(my $i = 0; $i < @$code; $i++) {
		my $redo;
		$_ = $code->[$i];
		$t->text($t->text.$_);
		unless($state) {
			if(/[$op->[0]]/) { $state = 'op'; } # オペレータ
			elsif(/\d/) { $state = 'number'; }	# 数字
			elsif(/\s/) { $state = 'space'; }	# スペース
			else { $state = 'ident'; }			# それ以外はident
		}
		elsif($state eq 'number' && !/\d/) { $t->kind($state); $redo = 1; }
		elsif($state eq 'space'	 && !/\s/) { $t->kind($state); $redo = 1; }
		elsif($state eq 'ident'	 && /[\s$op->[0]]/) { $t->kind($state); $redo = 1; }
		# 文字列の処理
		elsif($state =~ /^(string|char)$/) {
			if(/$qu->{$state}/) { $t->kind($state); }
			elsif($_ eq $this->{esc}) { $state .= '_esc'; }
		}
		elsif($state =~ /^(.+)_esc$/) { $state = $1; }
		# コメントの処理
		elsif('ARRAY' eq ref $this->{comment}) {
			foreach my $cmt(@{$this->{comment}}) {
				$t->kind($state) if $state eq "comment_$cmt->{begin}" && substr($t->text, -length($cmt->{end})) eq $cmt->{end};
			}
		}

		# オペレータの処理
		if($state eq 'op') {
			$t->text('	'), $state = 'space' if $t->text eq '　';
			my $c = [$_, $_.$code->[$i+1], $_.$code->[$i+1].$code->[$i+2]];
			foreach my $j(0..2) {
				$t->text($c->[$j]), $i += $j if $j > 0 && grep{$c->[$j] eq $_} @{$op->[$j]};
				if('ARRAY' eq ref $this->{comment}) {
					foreach my $cmt(@{$this->{comment}}) {
						$state = "comment_$cmt->{begin}" if $t->text eq $cmt->{begin};
					}
				}
			}
			if($state eq 'op') {
				while(my($k, $v) = each %$qu) {
					$state = $k if $t->text eq $v;
				}
			}
			$t->kind($state) if $state eq 'op';
		}

		$t->kind($state) if /^$/;
		if(/\012|\015/) {
			$t->kind($state =~ /^(.+)_/ ? $1 : $state);
			$t->text(substr $t->text, 0, length($t->text) - 1);
			$t->{text} =~ s/\t/	   /gm if $t->value =~ /^space_.*\t/;
			$t->{text} =~ s/　/	 /gm   if $t->value =~ /^space_.*　/;
			$this->end->add($t) unless $t->text eq '';
			$this->end->add(new Token("\n", 'space'));
			$t = new Token();
			if('ARRAY' eq ref $this->{comment}) {
				 foreach my $cmt(@{$this->{comment}}) {
					undef $state if $state eq "comment_$cmt->{begin}" && $cmt->{end} eq '\n';
				 }
			 }
			$i++ if /\015/ && $code->[$i+1] =~ /\012/;
		} elsif($t->kind) {
			$t->kind($1) if $t->kind =~ /^(.+)_/;
			$t->text(substr $t->text, 0, length($t->text) - 1) if $redo;
			$t->{text} =~ s/\t/	   /gm if $t->value =~ /^space_.*\t/;
			$t->{text} =~ s/　/	 /gm   if $t->value =~ /^space_.*　/;
			$this->end->add($t) unless $t->text eq '';
			$t = new Token();
			undef $state;
			redo if $redo;
		}
	} # end for
	
	$this->setLine;
	$this->debug('End Analyze');
}

#-------------------------------------------------------------------------------
# 各トークンに行番号および縦位置などを付加する
#-------------------------------------------------------------------------------
sub setLine {
	my($this) = @_;
	$this->debug('setLine');
	my $line = 1;
	my $colum = 1;
	for(my $t = $this->begin; !$t->eof; $t = $t->next) {
		$t->{file} = $this->{file};
		$t->{line} = $line;
		$t->{colum}= $colum;
		$t->{len} = 0;
		$t->{len} += $_ foreach map{/[\x20-\x7f]/ ? 1 : 2} split //, $t->text;
		$colum += $t->{len};
		$t->{colend} = $colum;
		$colum = 1, $line++ if $t->text =~ /\n/;
	}
}

#-------------------------------------------------------------------------------
# デバック用プリント
#-------------------------------------------------------------------------------
sub debug {
	my($this, @msg) = @_;
	print '[LexicalAnalyzer]' . join(',', @msg). "\n" if $this->{debug};
}

#===============================================================================
# 宣言を探す
#===============================================================================
sub find_define {
	my($this, $name, $target) = @_;

    $target = 'method' unless $target;
	$this->debug("find_define:$name target:$target");

    my $end_define = '^op_[\{;:]$';
    $end_define = '^op_[\{;]$' if $target eq 'class';

	my $ret = [];
	for(my $t = $this->begin; !$t->eof; $t = $t->next) {
		next unless $t->kind eq 'ident' && $t->text eq $name;

		$this->debug("find:". $t->line. ":". $t->text);

		my $def;				# 宣言かどうか
		my $count = 0;			# テンプレート用カウンタ
		my $cls;
		my($begin, $end) = ($t, $t);
		while(!$begin->bof) {
			$begin = $begin->prev;
			$_ = $begin->value;
			next if /^(space_.*|comment_.*|op_[\*&]+)$/;
			$cls = 1, next if /^op_::$/;
			$def = 1, next if /^ident_/ && !$cls;
			undef($cls), next if /^ident_/;
			$count++, next if $_ eq 'op_>';
			$count--, next if $_ eq 'op_<';
			last if $count < 0;
			last unless $count > 0 && /^(number_.*|op_,)$/;
		}

        next unless $def;

		next if $count;
		while(!$end->eof) {
			$end = $end->next;
			$_ = $end->value;
#			next if /^(space|comment)_/;
#			$count++, next if $_ eq 'op_(';
#			if($_ eq 'op_)') {
#				$count--;
#				last if $count < 0;
#				$end = $end->next, last unless $count;
#				next;
#			}
			last if /$end_define/;
		}

		next if $count;
		$begin = $begin->next;
		$begin = $begin->next while $begin->kind =~ /^(space|comment)$/;
		$end   = $end->prev;
		$end   = $end->prev	  while $end->kind	 =~ /^(space|comment)$/;
        
		my $token = new TokenAnalyzer();    # ({debug=>$this->{debug}});
        $token->append($begin, $end);
        for(my $q = $token->begin; !$q->eof; $q = $q->next) {
            next unless $q->kind eq 'ident' && $q->text eq $name;
            $token->{this} = $q;
        }
        
		push @$ret, $token;
	
		$this->debug('hit:'. $token->tokens());
	}
	$this->debug('end find_define');

	return $ret;
}

1;
