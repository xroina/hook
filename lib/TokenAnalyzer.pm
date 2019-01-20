#===============================================================================
# トークンアナライザ
#===============================================================================
package TokenAnalyzer;

BEGIN {
	unshift @INC, $0 =~ /^(.*?)[^\/]+$/;
	unshift @INC, readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;
use Token;

#-------------------------------------------------------------------------------
# オブジェクト作成
#-------------------------------------------------------------------------------
sub new {
	my($this, $params) = @_;
	$this = bless {
		begin => new Token(),
		end   => new Token(),
		esc   => '\\',
		comment => [
			{begin=>'/*', end=>'*/'},
			{begin=>'//', end=>'\n'}
		]
	}, $this;
	$this->{begin}->add($this->{end});
	$this->{$_} = $params->{$_} foreach keys %$params;
	return $this;
}

#-------------------------------------------------------------------------------
# デバック用プリント
#-------------------------------------------------------------------------------
sub debug {
	my($this, @msg) = @_;
	print '[TokenAnalyzer] ' . join(',', @msg). "\n" if $this->{debug};
}

#-------------------------------------------------------------------------------
# トークンの先頭を取得
#-------------------------------------------------------------------------------
sub begin {
	my($this) = @_;
	return $this->{begin}->next;
}

#-------------------------------------------------------------------------------
# トークンの末尾を取得
#-------------------------------------------------------------------------------
sub end {
	my($this) = @_;
	return $this->{end}->prev;
}

#-------------------------------------------------------------------------------
# トークン取得
#-------------------------------------------------------------------------------
sub get {
	my($this, $begin, $end, $kind) = @_;
	$kind = '' unless $kind;
	my $flag; $flag = 1, $kind = $1 if $kind =~ /^!(.*)$/;
	if(defined $begin && defined $end) {
		$begin = $this->get($begin)->next unless 'Token' eq ref $begin;
		$end   = $this->get($end)		  unless 'Token' eq ref $end;
		my $ret = [];
		for(my $t = $begin; !$t->eof($end); $t = $t->next) {
			push @$ret, $t if $flag ? $t->value !~ /^($kind)$/ : $t->value =~ /^($kind)$/;
		}
		return $ret;
	}

	if(defined $begin) {
		my $ret;
		if('Token' eq ref $begin) { $ret = $begin; } else {
			for(my($t, $i) = ($this->begin, 0); !$t->eof; $t = $t->next, $i++) {
				$ret = $t,last if $i == $begin;
			}
		}
		return $ret if $flag ? $this->value !~ /^($kind)$/ : $this->value =~ /^($kind)$/;
		return new Token();
	}

	my $ret = [];
	for(my $t = $this->begin; !$t->eof; $t = $t->next) {
		push @$ret, $t if $flag ? $this->value !~ /^($kind)$/ : $this->value =~ /^($kind)$/;
	}
	return $ret;
}

#-------------------------------------------------------------------------------
# トークン追加
#-------------------------------------------------------------------------------
sub append {
	my($this, $begin, $end) = @_;
	unless($end) {
	    $this->debug($begin->debug);
        $this->end->add(new Token($begin));
	    return;
	}

    for(my $t = $begin; !$t->eof($end); $t = $t->next) {
        $this->debug($t->debug);
        $this->end->add(new Token($t)) unless $t->bof || $t->eof;
    }
}

#-------------------------------------------------------------------------------
# トークンを頭に追加
#-------------------------------------------------------------------------------
sub first {
	my($this, $begin, $end) = @_;
	$end = $begin unless $end;
    my $first = $this->{begin};

    for(my $t = $begin; !$t->eof($end); $t = $t->next) {
        $this->debug($t->debug);
        unless($t->bof || $t->eof) {
            my $token = new Token($t);
            $first->add($token);
            $first = $first->next;
        }
    }
}

#-------------------------------------------------------------------------------
# トークン文字列取得(デバック用)
#-------------------------------------------------------------------------------
sub tokens {
	my($this, $begin, $end) = @_;
	$begin = $this->begin unless $begin;
	$end   = $this->end	  unless $end;
	my $ar = [];
	push @$ar, '[BOF]' if $begin->bof;
	my $t;
	for($t = $begin; !$t->eof; $t = $t->next) {
		push @$ar, $t->value if $t->kind !~ /^(space|comment)$/;
		last if $t == $end;
	}
	push @$ar, '[EOF]' if $t->eof;
	return join ' ', @$ar;
}

#-------------------------------------------------------------------------------
# トークン文字列取得2(デバック用アドレス表記)
#-------------------------------------------------------------------------------
sub print {
	my($this, $begin, $end) = @_;
	$begin = $this->begin unless $begin;
	$end   = $this->end	  unless $end;
	my $ar = [];
	my $t = $begin;
	push @$ar, "begin:", $begin->debug, "\n";
	push @$ar, "end:",   $end->debug,   "\n";
	push @$ar, '[BOF]' if $t->prev->bof;
	while(!$t->eof($end)) {
		push @$ar, "'", $t->debug, "'";
		$t = $t->next;
	}
	push @$ar, '[EOF]' if $t->eof;
	push @$ar, '[END]' if $t == $end;
	return join '', @$ar;
}

#-------------------------------------------------------------------------------
# トークン文字列取得
#-------------------------------------------------------------------------------
sub string {
	my($this, $begin, $end) = @_;
	$begin = $this->begin unless $begin;
	$end   = $this->end	  unless $end;
	my $ar = [];
	for(my $t = $begin; !$t->eof($end); $t = $t->next) {
		next if $t->kind =~ /^(comment|space)$/;
		push @$ar, $t->text;
	}
	return join ' ', @$ar;
}

1;
