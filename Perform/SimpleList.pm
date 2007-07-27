package DBIx::Perform::SimpleList;
use strict;
use base 'Exporter';
use Data::Dumper;
use DBI;

our $VERSION = '0.69';

our @EXPORT_OK = qw(	&new
  &is_empty
  &is_last
  &is_first
  &look_ahead
  &current_row
  &next_row
  &previous_row
  &get_value_at
  &add_row
  &insert_row
  &replace_row
  &remove_row
  &last_row
  &first_row
  &list_size
  &list_cursor
  &stuff_list
  &reset
  &iterate_list
  &clear_list
  &clone_list
  &dump_list
);

our @rows = ();

sub new {
    my $class = shift;

    bless my $self = {
        top  => 0,
        size => 0,
        iter => 0,
        rows => undef,
    } => ( ref $class || $class );
    return $self;
}

sub is_empty {
    my $self = shift;

    $self->{size} == 0 ? return 1 : return undef;
}

sub not_empty {
    my $self = shift;

    $self->{size} == 0 ? return undef : return 1;
}

sub is_first {
    my $self = shift;

    $self->{iter} == 0 ? return 1 : return undef;
}

sub look_ahead {
    my $self = shift;

    return undef if $self->is_last;

    my $next = $self->next_row;
    $self->previous_row;

    return $next;
}

sub is_last {
    my $self = shift;

    $self->{iter} == $self->{top} ? return 1 : return undef;
}

sub reset {
    my $self = shift;

    $self->{iter} = -1;
}

sub iterate_list {
    my $self = shift;

    return undef if $self->is_last;

    return $self->next_row;
}

sub current_row {
    my $self = shift;

    return $self->{rows}->[ $self->{iter} ];
}

sub next_row {
    my $self   = shift;
    my $offset = shift;

    if ( defined($offset) ) {
        $self->{iter} += $offset;
    }
    else { ++$self->{iter}; }

    $self->{iter} = $self->{top} if $self->{iter} > $self->{top};

    #$self->{iter} = 0 if $self->{iter} > $self->{top};

    return $self->{rows}->[ $self->{iter} ];
}

sub previous_row {
    my $self   = shift;
    my $offset = shift;

    if ( defined($offset) ) {
        $self->{iter} -= $offset;
    }
    else { --$self->{iter}; }

    $self->{iter} = 0 if $self->{iter} < 0;

    #$self->{iter} = $self->{top} if $self->{iter} < 0;

    return $self->{rows}->[ $self->{iter} ];
}

sub get_value_at {
    my $self  = shift;
    my $value = shift;
    my $index = shift;

    die "index greater than list size" if !( $self->{size} > $index );

    for ( my $count = 0 ; $count < $index ; $self->{iter}++ ) { }

    $self->add($value);

    return $self->{rows}->[ $self->{iter} ];
}

sub add_row {
    my $self = shift;
    my $row  = shift;

    return undef if !defined($row);

    ++$self->{top} if $self->{size} != 0;
    $self->{rows}->[ $self->{top} ] = $row;
    ++$self->{size};
    $self->{iter} = $self->{top};

    return $self->last_row;
}

sub list_cursor {
    my $self = shift;

    return $self->{iter};
}

sub remove_row {
    my $self = shift;

    return undef if $self->{top} == 0;

    my $i = $self->{iter};

    while ( $i < $self->{top} ) {
        $self->{rows}[$i] = $self->{rows}[$i+1];
        $i++;
    }

    --$self->{size};
    --$self->{top};

    return $self->current_row;
}

sub insert_row {
    my $self = shift;
    my $row  = shift;

    return undef if !defined($row);

    if ( $self->{size} == 0 ) {
        $self->{rows}->[0] = $row;
        ++$self->{size};
    }

    if ( $self->{iter} != $self->{top} ) {
        my @tmp = @{ $self->{rows} };
        my @b   = ();
        my $i   = 0;

        foreach my $r (@tmp) {
            if ( $i == $self->{iter} ) {
                $b[$i] = $row;
                $i++;
            }
            $b[$i] = $r;
            $i++;
        }
        $self->{rows} = \@b;
    }
    else { $self->{rows}->[ $self->{top} ] = $row; }

    ++$self->{size};
    ++$self->{top};

    return $self->current_row;
}

sub replace_row {
    my $self = shift;
    my $row  = shift;

    return undef if !defined($row);

    $self->{rows}[ $self->{iter} ] = $row;

    return $self->current_row;
}

sub last_row {
    my $self = shift;

    $self->{iter} = $self->{top};

    return $self->{rows}->[ $self->{top} ];
}

sub first_row {
    my $self = shift;

    $self->{iter} = 0;
    return $self->{rows}->[0];
}

sub list_size {
    my $self = shift;

    return $self->{size};
}

sub stuff_list {
    my $self  = shift;
    my $query = shift;
    my $vals  = shift;
    my $db    = shift;

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my @vals     = @$vals;

    $self->clear_list;

    my $sth = $db->prepare_cached($query);

    unless ($sth) {
        $GlobalUi->display_comment("DB Error on prepare");
        $GlobalUi->display_error("$DBI::errstr");
        return undef;
    }

    unless ( defined( $sth->execute(@vals) ) ) {
        $GlobalUi->display_comment("DB Error on prepare");
        $GlobalUi->display_error("$DBI::errstr");
        return undef;
    }

    while ( my $ref = $sth->fetchrow_hashref() ) {
        $self->add_row($ref);
    }

    $self->{iter} = 0;
    return $self->first_row;
}

sub clear_list {
    my $self = shift;

    $self->{size} = 0;
    $self->{iter} = 0;
    $self->{top}  = 0;

    $self->{rows} = ();
}

sub clone_list {
    my $self = shift;
    my $list = new DBIx::Perform::SimpleList;

    my @a;
    my $i = 0;

    while ( $i <= $self->{top} ) {
        $a[$i] = $self->{rows}->[$i];
        $i++;
    }
    $list->{rows} = \@a;
    $list->{iter} = 0;
    $list->{size} = $self->{size};
    $list->{top}  = $self->{top};

    return $list;
}

sub dump_list {
    my $self = shift;

    print STDERR "top: $self->{top}\n";
    print STDERR "iter: $self->{iter}\n";
    print STDERR "size: $self->{size}\n";
    print STDERR "rows array: \n";
    print STDERR Dumper( $self->{rows} );
}

1;
