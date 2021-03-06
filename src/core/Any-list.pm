role Hash { ... }
class Range { ... }

augment class Any {
    method Seq() { 
        Seq.new(self.list)
    }

    method all() {
        all(self.list)
    }

    method any() {
        any(self.list)
    }

    method one() {
        one(self.list)
    }

    method none() {
        none(self.list)
    }

    our Str multi method join($separator = '') {
        ~pir::join__SsP($separator, self.flat.eager);
    }

    multi method elems() {
        1;
    }

    multi method flat() { self.list.flat }

    our multi method map(&block) { self.list.map(&block); }

    our multi method sort(&by = &infix:<cmp>) { self.list.sort(&by); }

    method rotate($n = 1) { self.list.rotate($n); }

    multi method first(Mu $test) {
        for @.list {
            if $_ ~~ $test {
                return $_;
            }
        }

        fail('No values matched');
    }

    our multi method grep(Mu $test) {
        gather {
            for @.list {
                take $_ if $_ ~~ $test;
            }
        }
    }

    multi method reverse() {
        my @result = ();
        for @.list {
            @result.unshift($_);
        }
        return @result;
    }

    multi method end() { self.elems - 1; }

    # CHEAT: this should take an ordering parameter
    # And use the FIRST: phaser
    multi method min($by = { $^a cmp $^b}) {
        die "Unable to handle non-closure Ordering yet" unless $by ~~ Code;
        my $cmp = $by.signature.params.elems == 2 ?? $by !! { $by($^a) cmp $by($^b) };

        my $min = +Inf;
        my $first-time = Bool::True;
        for @.list {
            if $first-time {
                $min = $_;
                $first-time = Bool::False;
                next;
            }
            if $cmp($_, $min) == -1 {
                $min = $_;
            }
        }
        $min;
    }

    # CHEAT: this should take an ordering parameter
    # And use the FIRST: phaser
    multi method max($by = { $^a cmp $^b}) {
        die "Unable to handle non-closure Ordering yet" unless $by ~~ Code;
        my $cmp = $by.signature.params.elems == 2 ?? $by !! { $by($^a) cmp $by($^b) };

        my $max = -Inf;
        my $first-time = Bool::True;
        for @.list {
            if $first-time {
                $max = $_;
                $first-time = Bool::False;
                next;
            }
            if $cmp($_, $max) == 1 {
                $max = $_;
            }
        }
        $max;
    }

    # CHEAT: this should take an ordering parameter
    # And use the FIRST: phaser
    multi method minmax($by = { $^a cmp $^b}) {
        die "Unable to handle non-closure Ordering yet" unless $by ~~ Code;
        my $cmp = $by.signature.params.elems == 2 ?? $by !! { $by($^a) cmp $by($^b) };

        my $min = +Inf;
        my $max = -Inf;
        my $excludes_min = Bool::False;
        my $excludes_max = Bool::False;

        my $first-time = Bool::True;
        for @.list {
            when Range {
                if $first-time {
                    $min = $_.min;
                    $max = $_.max;
                    $excludes_min = $_.excludes_min;
                    $excludes_max = $_.excludes_max;
                    $first-time = Bool::False;
                    next;
                }
                if $cmp($_.min, $min) == -1 {
                    $min = $_;
                    $excludes_min = $_.excludes_min;
                }
                if $cmp($_.max, $max) == 1 {
                    $max = $_;
                    $excludes_max = $_.excludes_max;
                }
            }

            if $first-time {
                $min = $_;
                $max = $_;
                $first-time = Bool::False;
                next;
            }
            if $cmp($_, $min) == -1 {
                $min = $_;
                $excludes_min = Bool::False;
            }
            if $cmp($_, $max) == 1 {
                $max = $_;
                $excludes_max = Bool::False;
            }
        }
        Range.new($min,
                  $max,
                  :excludes_min($excludes_min),
                  :excludes_max($excludes_max));
    }

    #CHEAT: Simplified version which we can hopefully sneak by ng.
    multi method pick() {
        my @l = @.list.Seq;
        @l[floor(@l.elems.rand)];
    }

    multi method pick($num is copy = 1, :$replace) {
        my @l = @.list.Seq;

        if ($num == 1) {
            return @l[floor(@l.elems.rand)];
        }

        if $replace {
            gather {
                while ($num > 0) {
                    my $idx = floor(@l.elems.rand());
                    take @l[$idx];
                    --$num;
                }
            }
        } else {
            gather {
                while ($num > 0 and @l.elems > 0) {
                    my $idx = floor(@l.elems.rand());
                    take @l[$idx];
                    @l.splice($idx,1);
                    --$num;
                }
            }
        }
    }

    multi method pick(Whatever, :$replace) {
        self.pick(Inf, :$replace);
    }

    multi method classify($test) {
        my %result;
        for @.list {
            my $k = $_ ~~ $test;
            %result{$k} //= [];
            %result{$k}.push: $_;
        }
        %result.pairs;
    }

    multi method reduce(Code $expression is rw) {
        my $arity = $expression.?count || 2; # second half is a CHEAT
        fail('Cannot reduce() using a unary or nullary function.')
            if $arity < 2;
        fail('Can only reduce() using a binary function for now.')
            if $arity > 2;

        my @args = ();
        for @.list {
            @args.push($_);
            if (@args == $arity) {
                my $res = $expression.(@args[0], @args[1]);
                # my $res = $expression.(|@args);
                @args = ($res);
            }
        }

        fail('Cannot reduce() empty list') unless @args > 0;

        if @args > 1 {
            if @args < $expression.arity {
                warn (@args -1) ~ " trailing item(s) in reduce";
            } else {
                return $( $expression.(@args[0], @args[1]) );
                # return $( $expression.(|@args) );
            }
        }
        return @args[0];
    }

    # This needs a way of taking a user-defined comparison
    # specifier, but AFAIK nothing has been spec'd yet.
    # CHEAT: Almost certainly should be hashed on something
    # other than the stringification of the objects.
    multi method uniq() {
        my %seen;
        gather for @.list {
             unless %seen{$_} {
                 take $_;
                 %seen{$_} = 1;
             }
        }
    }

    multi method kv() {
        my $i = 0;
        gather for $.list -> $value {
            my $key = $i++;
            take $key;
            take $value;
        }
    }

    multi method keys() {
        my $i = 0;
        gather for $.list -> $value {
            my $key = $i++;
            take $key;
        }
    }

    multi method values() {
        gather for $.list -> $value {
            take $value;
        }
    }

    multi method pairs() {
        self.kv.map(-> $key, $value { $key => $value; });
    }

    our multi method postcircumfix:<[ ]>() { self.list }

    our multi method postcircumfix:<[ ]>(&block) { self[&block(self.elems)]; }

    our multi method postcircumfix:<[ ]>(@pos) {
        my $result = pir::new__ps('ResizablePMCArray');
        for @pos {
            pir::push($result, self[$_])
        }
        Q:PIR {
            $P0 = find_lex '$result'
            %r = '&infix:<,>'($P0 :flat)
        }
    }

    our multi method postcircumfix:<[ ]>($pos) {
        fail "Cannot use negative index $pos on {self.WHO}" if $pos < 0;
        self.at_pos($pos)
    }

    method at_pos($pos) {
        if self.defined {
            fail ".[$pos] out of range for type {self.WHAT}" if $pos != 0;
            return self;
        }
        my $z = Any!butWHENCE(
                    { self.defined || &infix:<=>(self, Array.new);
                      pir::set__vQiP(self!fill($pos+1), $pos, $z);
                    }
                );
    }

    our multi method postcircumfix:<{ }>() {
        self.values()
    }

    our multi method postcircumfix:<{ }>(@keys) {
        my $result = pir::new__ps('ResizablePMCArray');
        for @keys {
            pir::push($result, self{$_})
        }
        Q:PIR {
            $P0 = find_lex '$result'
            %r = '&infix:<,>'($P0 :flat)
        }
    }

    our multi method postcircumfix:<{ }>($key) { self.at_key($key) }

    method at_key($key) {
        fail "postcircumfix:<{ }> not defined for type {self.WHAT}"
            if self.defined;
        my $z = Any!butWHENCE(
                    { self.defined || &infix:<=>(self, Hash.new);
                      pir::set__vQsP($!storage, $key, $z);
                    }
                );
    }

    method !butWHENCE(&by) {
        pir::setprop__0PsP(pir::clone__PP(pir::descalarref__PP(self)), 'WHENCE', &by);
    }
}

proto sub classify($matcher, *@values) { @values.classify($matcher) }
proto sub join (Str $separator = '', *@values) { @values.join($separator); }
proto sub reverse(@values) { @values.reverse; }
multi sub reverse(*@v) { @v.reverse; }
proto sub end(@array) { @array.end; }
proto sub grep(Mu $test, *@values) { @values.grep($test); }
proto sub first(Mu $test, @values) { @values.first($test); }
proto sub min($by, *@values) { @values.min($by); }
proto sub max($by, *@values) { @values.max($by); }
proto sub minmax($by, *@values) { @values.minmax($by); }
proto sub uniq(@values) { @values.uniq; }
proto sub pick ($num, :$replace, *@values) { @values.pick($num, :$replace); }
proto sub map(&mapper, *@values) { @values.map(&mapper); }
proto sub kv(@array) { @array.kv; }
proto sub keys(@array) { @array.keys; }
proto sub values(@array) { @array.values; }
proto sub pairs(@array) { @array.pairs; }
proto sub rotate(@array, $n = 1) { @array.rotate($n); }

multi sub sort(*@values, :&by) {
    my &x = &by // (@values[0] ~~ Callable ?? @values.shift !! &infix:<cmp> );
    @values.sort(&x);
}

# vim: ft=perl6
