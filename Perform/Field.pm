
package DBIx::Perform::Field;

use strict;
use warnings;
use Curses;
use Math::Trig;
use DBIx::Perform::Widgets::ButtonSet;
use DBIx::Perform::AttributeGrammar;
use Parse::RecDescent;
use Data::Dumper;
use base 'Exporter';

our $VERSION = '0.691';

# debug: set (unset) in runtime env
$::TRACE      = $ENV{TRACE};
$::TRACE_DATA = $ENV{TRACE_DATA};

# Global User Interface
#our $GlobalUi = $DBIx::Perform::GlobalUi;

# $Field methods
our @EXPORT_OK = qw(
  &new
  &duplicate
  &parse_line
  &print
  &print_lookup_hash
  &print_field_tag_join_hash
  &print_include_values
  &scalar_number_or_letter
  &is_number
  &is_char
  &is_serial
  &get_comments
  &set_comments
  &get_field_tag
  &get_names
  &set_value
  &get_value
  &display_status_message
  &display_error_message
  &is_any_numeric_db_type
  &is_real_db_type
  &is_integer_db_type
  &is_numeric_db_type
  &parse_db_type
  &set_field_null_ok
  &set_field_size
  &set_field_type
  &format_value_for_display
  &format_value_for_database
  &handle_verify_joins
  &handle_queryclear_attribute
  &handle_shift_attributes
  &handle_right_attribute
  &handle_subscript_attribute
  &handle_picture_attribute
  &handle_date_attribute
  &handle_format_attribute
  &handle_money_attribute
  &validate_input
  &allows_focus
);

# Field ctor
sub new {
    my $class = shift;

    bless my $self = {
        line            => undef,
        field_tag       => undef,
        table_name      => undef,
        column_name     => undef,
        join_table      => undef,    # lookup fields objs
        join_column     => undef,    # lookup fields objs
        screen_name     => undef,
        value           => undef,    # Fields have a value at runtime
        type            => undef,    # Fields values have a type  at runtime
        db_type         => undef,    # table.column type in the database
        size            => undef,
#        dominant_table  => undef,    # for verify joins
#        dominant_column => undef,    # for verify joins

        # attributes
        active_tabcol  => undef, # for joining fields, the active table & column
        allowing_input => undef,
        autonext       => undef,
        comments       => undef,
        compress       => undef,
        displayonly    => undef,
        disp_only_type => undef,
        subscript_floor     => undef,
        subscript_ceiling   => undef,
        downshift           => undef,
        format              => undef,
        include             => undef,    # some form of include is defined
        include_values      => undef,
        null_ok             => undef,
        db_null_ok          => undef,
        invisible           => undef,
        field_tag_join_hash => undef,
        lookup_hash         => undef,
        picture             => undef,
        noentry             => undef,
        noupdate            => undef,
        queryclear          => undef,
        range_ceiling       => undef,
        range_floor         => undef,
        required            => undef,
        reverse             => undef,
        right               => undef,
        upshift             => undef,
        verify              => undef,
        wordwrap            => undef,
        zerofill            => undef,

    } => ( ref $class || $class );

    return $self;
}

sub duplicate {
    my $self = shift;

    my $new_field = $self->new;

    foreach my $att ( keys( %{$self} ) ) {
        $new_field->{$att} = $self->{$att};
    }

    return $new_field;
}

sub parse_line {
    my $self   = shift;
    my $line   = shift;
    my $tables = shift;

    my $val = undef;
    $self->{line} = $line;
    my $grammar = DBIx::Perform::AttributeGrammar::get_grammar;
    my $parser  = Parse::RecDescent->new($grammar);

    if ( my $ref = $parser->startrule( uc $line ) ) {
        my $href = @$ref[0];    # returned from the parser

        $self->{line} = $line;
        $val = lc $href->{field_tag};

        $self->{field_tag} = $val if defined $val;

        $val = lc $href->{table_name};
        $self->{table_name} = $val if defined $val;

        $val = lc $href->{column_name};
        $self->{column_name} = $val if defined $val;

        $val = lc $href->{data_type};
        $self->{type} = $val if defined $val;

        $val = $href->{value};
        $self->{value} = $val if defined $val;

        # attributes

        $val = $href->{ALLOWING_INPUT};
        $self->{allowing_input} = $val if defined $val;

        $val = $href->{AUTONEXT};
        $self->{autonext} = $val if defined $val;

        $val = $href->{COMMENTS};
        $self->{comments} = $val if defined $val;

        $val = $href->{COMPRESS};
        $self->{compress} = $val if defined $val;

        $val = $href->{DEFAULT};
        $self->{default} = $val if defined $val;

        $val = $href->{DISPLAYONLY};
        $self->{displayonly} = $val if defined $val;

        $val = $href->{data_type};
        $self->{disp_only_type} = $val if defined $val;

        $val = $href->{SUBSCRIPT_FLOOR};
        $self->{subscript_floor} = $val if defined $val;

        $val = $href->{SUBSCRIPT_CEILING};
        $self->{subscript_ceiling} = $val if defined $val;

        $val = $href->{DOWNSHIFT};
        $self->{downshift} = $val if defined $val;

        $val = $href->{FORMAT};
        $self->{format} = $val if defined $val;

        $val = $href->{INCLUDE_VALUES};
        $self->{include_values} = $val if defined $val;

        $val = $href->{INCLUDE_NULL_OK};
        $self->{null_ok} = $val if defined $val;

        $val = $href->{INVISIBLE};
        $self->{invisible} = $val if defined $val;

        $val = $href->{LOOKUP_HASH};
        $self->{lookup_hash} = $val if defined $val;

        $val = $href->{NOENTRY};
        $self->{noentry} = $val if defined $val;

        $val = $href->{NOTNULL};
        $self->{noentry} = $val if defined $val;

        $val = $href->{NOUPDATE};
        $self->{noupdate} = $val if defined $val;

        $val = $href->{PICTURE};
        $self->{picture} = $val if defined $val;

        $val = $href->{QUERYCLEAR};
        $self->{queryclear} = $val if defined $val;

        $val = $href->{RANGE_CEILING};
        $self->{range_ceiling} = $val if defined $val;

        $val = $href->{RANGE_FLOOR};
        $self->{range_floor} = $val if defined $val;

        $val = $href->{REQUIRED};
        $self->{required} = $val if defined $val;

        $val = $href->{REVERSE};
        $self->{reverse} = $val if defined $val;

        $val = $href->{RIGHT};
        $self->{right} = $val if defined $val;

        $val = $href->{UPSHIFT};
        $self->{upshift} = $val if defined $val;

        $val = $href->{VERIFY};
        $self->{verify} = $val if defined $val;

        $val = $href->{WORDWRAP};
        $self->{wordwrap} = $val if defined $val;

        $val = $href->{ZEROFILL};
        $self->{zerofill} = $val if defined $val;

        $val = $href->{FIELD_TAG_JOIN_HASH};
        $self->{field_tag_join_hash} = $val if defined $val;

        $ref =
          undef;    # reset the grammar return hash to parse the next input line
        return $self;

    }
    else {
        warn "\nLINE: $line\n";
        warn "...line seems invalid\n\n";
        return undef;
    }
}

sub print {
    my $self = shift;
    my $str;

    print STDERR "-----------------------\n";
    $str = $self->{line};
    print STDERR "line: $str\n" if $str;
    print STDERR "- - - - - - - - - - - -\n";
    $str = $self->{field_tag};
    print STDERR "field_tag:           $str\n" if defined($str);
    $str = $self->{table_name};
    print STDERR "table name:          $str\n" if defined($str);
    $str = $self->{column_name};
    print STDERR "column name:         $str\n" if defined($str);
    $str = $self->{join_table};
    print STDERR "join table:          $str\n" if defined($str);
    $str = $self->{join_column};
    print STDERR "join column:         $str\n" if defined($str);
    $str = $self->{screen_name};
    print STDERR "screen name:         $str\n" if defined($str);
    $str = $self->{type};
    print STDERR "type:                $str\n" if defined($str);
    $str = $self->{db_type};
    print STDERR "db_type:             $str\n" if defined($str);
    $str = $self->{size};
    print STDERR "size:                $str\n" if defined($str);
    $str = $self->{value};
    print STDERR "value:               $str\n" if defined($str);

    print STDERR "\nattributes:\n" if defined( $self->{column_name} );

    $str = $self->{displayonly};
    print STDERR "   displayonly:      $str\n" if defined($str);
    $str = $self->{disp_only_type};
    print STDERR "   displayonly type: $str\n" if defined($str);
    $str = $self->{subscript_floor};
    print STDERR "   subscript floor:  $str\n" if defined($str);
    $str = $self->{subscript_ceiling};
    print STDERR "   subscript ceiling:$str\n" if defined($str);
    $str = $self->{active_tabcol};
    print STDERR "   active t\/c:      $str\n" if defined($str);
    $str = $self->{allowing_input};
    print STDERR "   allowing_input:   $str\n" if defined($str);
    $str = $self->{autonext};
    print STDERR "   autonext:         $str\n" if defined($str);
    $str = $self->{comments};
    print STDERR "   comments:         $str\n" if defined($str);
    $str = $self->{compress};
    print STDERR "   compress:         $str\n" if defined($str);
    $str = $self->{default};
    print STDERR "   default:          $str\n" if defined($str);
    $str = $self->{downshift};
    print STDERR "   downshift:        $str\n" if defined($str);
    $str = $self->{format};
    print STDERR "   format:           $str\n" if defined($str);
    $str = $self->{include};
    print STDERR "   include:          $str\n" if defined($str);
    $str = $self->{null_ok};
    print STDERR "   null_ok:          $str\n" if defined($str);
    $str = $self->{db_null_ok};
    print STDERR "   db_null_ok:       $str\n" if defined($str);
    $str = $self->{invisible};
    print STDERR "   invisible:        $str\n" if defined($str);
    $str = $self->{noentry};
    print STDERR "   noentry:          $str\n" if defined($str);
    $str = $self->{noupdate};
    print STDERR "   noupdate:         $str\n" if defined($str);
    $str = $self->{picture};
    print STDERR "   picture:          $str\n" if defined($str);
    $str = $self->{queryclear};
    print STDERR "   queryclear:       $str\n" if defined($str);
    $str = $self->{range_floor};
    print STDERR "   range floor:      $str\n" if defined($str);
    $str = $self->{range_ceiling};
    print STDERR "   range ceiling:    $str\n" if defined($str);
    $str = $self->{required};
    print STDERR "   required:         $str\n" if defined($str);
    $str = $self->{reverse};
    print STDERR "   reverse:          $str\n" if defined($str);
    $str = $self->{right};
    print STDERR "   right:            $str\n" if defined($str);
    $str = $self->{upshift};
    print STDERR "   upshift:          $str\n" if defined($str);
    $str = $self->{verify};
    print STDERR "   verify:           $str\n" if defined($str);
    $str = $self->{wordwrap};
    print STDERR "   wordwrap:         $str\n" if defined($str);
    $str = $self->{zerofill};
    print STDERR "   zerofill:         $str\n" if defined($str);

    $self->print_include_values;
    print STDERR "\n";

    $self->print_lookup_hash;
    print STDERR "\n";

    $self->print_field_tag_join_hash;
    print STDERR "\n";

    return $self;
}

sub print_lookup_hash {
    my $self = shift;

    my %lookup1;
    my %lookup;
    if ( defined( $self->{lookup_hash} ) ) {
        %lookup1 = %{ $self->{lookup_hash} };
    }
    else { return; }

    foreach my $n ( keys(%lookup1) ) {
        my $instance_number = $n;
        my %lookup          = %{ $lookup1{$n} };

        foreach my $k ( keys(%lookup) ) {
            my $tag = $k;

            my $table_name  = $lookup{$k}->{table_name};
            my $column_name = $lookup{$k}->{column_name};
            my $join_table  = $lookup{$k}->{join_table};
            my $join_column = $lookup{$k}->{join_column};
            my $join_index  = $lookup{$k}->{join_index};
            my $active_tc   = $lookup{$k}->{active_tabcol};
            my $verify      = $lookup{$k}->{verify};

            print STDERR "   lookup:\n";
            print STDERR "      instance number:       $instance_number\n";
            print STDERR "            field tag:       $tag\n";
            print STDERR "           table name:       $table_name\n";
            print STDERR "          column name:       $column_name\n";
            print STDERR "           join_table:       $join_table\n"
              if defined($join_table);
            print STDERR "          join_column:       $join_column\n"
              if defined($join_column);
            print STDERR "               verify:       $verify\n"
              if defined($verify);
            print STDERR "               index:       $join_index\n"
              if defined($join_index);
        }
    }
}

sub print_field_tag_join_hash {
    my $self = shift;
    my %join;

    if ( defined( $self->{field_tag_join_hash} ) ) {
        %join = %{ $self->{field_tag_join_hash} };
    }
    else { return; }

    foreach my $k ( keys(%join) ) {
        my $tag = $k;

        my $join_table  = $join{$k}{join_table};
        my $join_column = $join{$k}->{join_column};
        my $verify      = $join{$k}->{verify};

        print STDERR "   join:\n";
        print STDERR "        hash id:           $tag\n";
        print STDERR "           join_table:       $join_table\n";
        print STDERR "          join_column:       $join_column\n";
        print STDERR "               verify:       $verify\n"
          if defined($verify);
    }
}

sub print_include_values {
    my $self = shift;

    my %values = %{ $self->{include_values} }
      if defined( $self->{include_values} );
    return if !defined( $self->{include_values} );

    print STDERR "   include values:\n";
    print STDERR "        ";
    foreach my $k ( keys(%values) ) {
        print STDERR "$k, ";
    }
    print STDERR "\n";
}

sub scalar_number_or_letter {
    my $self = shift;
    my $char = shift;

    return undef if !defined($char);

    if ( $char    =~ /[-+.0-9]/ ) { return "NUMBER"; }
    if ( uc $char =~ /[A-Z]/ ) { return "LETTER"; }

    return undef;
}

sub is_number {

    my $self = shift;
    my $char = shift;

    return undef if !defined($char);

    return 1 if $char =~ /[-+.0-9]/;
    return undef;
}

sub is_char {
    my $self = shift;
    my $char = shift;

    return undef if !defined($char);
    return 1 if uc $char =~ /[A-Z]/;
    return undef;
}

sub is_serial {
    my $self = shift;

    if ( defined( $self->{db_type} ) ) {
        return 1 if $self->{db_type} eq "SERIAL";
    }

    return undef;
}

sub get_comments {
    my $self = shift;
    return $self->{comments};
}

sub set_comments {
    my $self = shift;
    my $str  = shift;

    $self->{comments} = $str;
}

sub get_field_tag {
    my $self = shift;

    return $self->{field_tag};
}

sub get_names {
    my $self = shift;
    return undef if !defined($self);

    return ( $self->{field_tag}, $self->{table_name}, $self->{column_name} );
}

sub set_value {
    my $self  = shift;
    my $value = shift;

    #if ( defined $value ) { $value =~ s/\s*$//; undef $value if $value eq ''; }

    if ( defined $value ) { undef $value if $value eq ''; }
    $self->{value} = $value;
    return $value;
}

sub get_value {
    my $self = shift;

    return $self->{value};
}

# attribute support routines

sub display_status_message {
    my $self   = shift;
    my $msg_id = shift;

    my $GlobalUi = $DBIx::Perform::GlobalUi;

    return undef
      if !defined $msg_id;

    my $msg = $GlobalUi->{error_messages}->{$msg_id};

    $GlobalUi->display_status($msg) if defined($msg);

    return undef;
}

sub display_error_message {
    my $self   = shift;
    my $msg_id = shift;

    my $GlobalUi = $DBIx::Perform::GlobalUi;

    return undef
      if !defined $msg_id;

    my $app = $GlobalUi->{app_object};
    my $msg = $GlobalUi->{error_messages}->{$msg_id};

    $GlobalUi->display_error($msg) if defined($msg);

    return undef;
}

# bool - true if db field supports any number input
sub is_any_numeric_db_type {
    my $self = shift;

    my $db_type = uc $self->{db_type};

    my ( $type, $more ) = split( /\(/, $db_type );

    if (   $type eq "FLOAT"
        || $type eq "SMALLFLOAT"
        || $type eq "REAL"
        || $type eq "NUMERIC"
        || $type eq "DECIMAL"
        || $type eq "DEC"
        || $type eq "INTEGER"
        || $type eq "INT"
        || $type eq "SMALLINT" )
    {
        return 1;
    }

    return undef;
}

# bool - true if supports real numbers "m.n" input
sub is_real_db_type {
    my $self = shift;

    my $db_type = uc $self->{db_type};

    my ( $type, $more ) = split( /\(/, $db_type );

    if (   $type eq "FLOAT"
        || $type eq "SMALLFLOAT"
        || $type eq "REAL"
        || $type eq "NUMERIC"
        || $type eq "DECIMAL"
        || $type eq "DEC" )
    {
        return 1;
    }

    return undef;
}

# bool - true if db field supports natural number input
sub is_integer_db_type {

    my $self = shift;

    my $db_type = uc $self->{db_type};

    my ( $type, $more ) = split( /\(/, $db_type );

    if (   $type eq "INTEGER"
        || $type eq "INT"
        || $type eq "SMALLINT" )
    {
        return 1;
    }

    return undef;
}

# bool - true if db field supports only decimal input "m.n"
sub is_numeric_db_type {

    my $self = shift;

    my $db_type = uc $self->{db_type};

    my ( $type, $more ) = split( /\(/, $db_type );

    if (   $type eq "NUMERIC"
        || $type eq "DECIMAL"
        || $type eq "DEC" )
    {
        return 1;
    }

    return undef;
}

# break apart type info from the db
sub parse_db_type {
    my $self = shift;

    if ( defined $self->{displayonly} ) {
        my $type = uc $self->{type};
        return ( $type, 80 );    # guess at max
    }

    my ( $type, $size, $dc, $more, $mn );
    my $db_type = uc $self->{db_type};

    ( $type, $more ) = split( /\(/, $db_type );

    if ( defined $type ) {
        if (   $type eq "INTEGER"
            || $type eq "INT"
            || $type eq "SMALLINT"
            || $type eq "FLOAT"
            || $type eq "SMALLFLOAT"
            || $type eq "REAL"
            || $type eq "MONEY"
            || $type eq "SERIAL" )
        {

            # return an arbitrary, large value for size
            return ( $type, 10000 );
        }

        if (   $type eq "NUMERIC"
            || $type eq "DECIMAL"
            || $type eq "DEC" )
        {

            # handle n and m values for decimal digits

            ( $size, $mn ) = split( /\)/, $more );
            my ( $n, $m ) = split( /\./, $mn );
            $size = $n + $m + 1;
            warn "decimal: n: $n, m: $n, type: $type size: $size"
              if $::TRACE_DATA;

            return ( $type, $size );
        }

        if ( $type eq "DATE" ) { return ( $type, 9 ); }
    }

    # handle the rest

    ( $size, $dc ) = split( /\)/, $more ) if defined $more;
    warn "char: t: $type, size: $size" if $::TRACE_DATA;
    return ( $type, $size );
}

# include attribute null vs db null
sub set_field_null_ok {
    my $self = shift;

    my $db_null = $self->{db_null_ok};

    if ( !defined $db_null
        || ( defined $self->{include} && !defined $self->{null_ok} ) )
    {
        undef $self->{null_ok};
    }
    else { $self->{null_ok} = 1; }

    return $self->{null_ok};
}

# defined size vs db size
# no attempt is made to discover definition errors
sub set_field_size {
    my $self = shift;

    my ( $type, $size ) = $self->parse_db_type;

    # DB
    $self->{size} = $size;

    # PICTURE
    $self->{size} = length( $self->{picture} )
      if defined $self->{picture};

    # FORMAT
    $self->{size} = length( $self->{format} )
      if defined $self->{format};

    # SUBSCRIPTS
    if ( defined $self->{subscript_floor} ) {
        my $len = $self->{subscript_ceiling} - $self->{subscript_floor};
        $self->{size} = $len;
    }
    return undef;
}

# displayonly attribute type vs db type
# doesn't check for define errors
sub set_field_type {
    my $self = shift;

    my ( $type, $size ) = $self->parse_db_type;

    $self->{type} = $type;

    $self->{type} = $self->{disp_only_type}
      if defined $self->{disp_only_type};

    return undef;
}

# this calls most of the attribute "handle" routines
sub format_value_for_display {

    my $self = shift;
    my $val  = shift;
    my $pos  = shift;

    return ( $val, $pos, 0 ) if !defined $val;

    my $rc = 0;
    my ( $tag, $table, $col ) = $self->get_names;
    my $GlobalUi = $DBIx::Perform::GlobalUi;

    return ( $val, $pos, 0 ) if !defined $self->{db_type};
    # FIX:  keep this for a while
#    if ( !defined $self->{db_type} ) {
#        $self->print;
#        die "something wrong with db_type for $tag";
#    }

    # default: format numbers to db type
    # FORMAT - FLOAT REAL DECIMAL db_types
    if (   $self->{db_type} eq 'DECIMAL'
        || $self->{db_type} eq 'DEC'
        || $self->{db_type} eq 'FLOAT'
        || $self->{db_type} eq 'SMALLFLOAT'
        || $self->{db_type} eq 'REAL' )
    {
        my $tmp = $val;
        my @a = split /\./, $tmp;
        $val = $tmp . '.' . 0
          if $#a < 1;
        $GlobalUi->set_screen_value( $tag, $val );
    }

    ( $val, $pos, $rc ) = $self->handle_subscript_attribute( $val, $pos )
      if defined $self->{subscript_ceiling} && $rc == 0;

#    $rc = $self->handle_verify_joins;

    # needs much more testing
    ( $val, $pos, $rc ) = $self->handle_money_attribute( $val, $pos )
      if defined $self->{money} && $rc == 0;

    # pretty well exercised
    ( $val, $pos, $rc ) = $self->handle_shift_attributes( $val, $pos )
      if ( defined $self->{upshift} || defined $self->{downshift} ) && $rc == 0;
    ( $val, $pos, $rc ) = $self->handle_picture_attribute( $val, $pos )
      if defined $self->{picture} && $rc == 0;
    if ( defined $self->{format} && $rc == 0 ) {
        if (   uc $self->{format} eq "MM\/DD\/YYYY"
            || uc $self->{format} eq "MM\/DD\/YY" )
        {
            ( $val, $pos, $rc ) = $self->handle_date_attribute( $val, $pos );
        }
        else {
            $pos = ( length $val );
            ( $val, $pos, $rc ) = $self->handle_format_attribute( $val, $pos );
        }
    }
    ( $val, $pos, $rc ) = $self->handle_right_attribute( $val, $pos )
      if defined $self->{right} && defined $rc && $rc == 0;

    return ( $val, $pos, $rc );
}

# Prepares a value for db operations
sub format_value_for_database {

    my $self = shift;
    my $mode = shift;
    my $fo   = shift;    # optional

    my $val = $self->get_value;
    $val = '' if !defined $val;

    my $rc = 0;
    my ( $tag, $table, $col ) = $self->get_names;
    my $GlobalUi = $DBIx::Perform::GlobalUi;

    # test field value

    $rc = $self->validate_input( $val, $mode );
    return $rc if $rc != 0;

    # handle special cases for db input

    # SUBSCRIPT
    if (   defined $fo->{subscript_floor}
        && defined $fo->{subscript_ceiling} )
    {

        # get subscript info from $fo
        my $min  = $fo->{subscript_floor};
        my $max  = $fo->{subscript_ceiling};
        my $size = $max - $min;

        my $fo_val = $fo->get_value;
        $fo_val = '' if !defined $fo_val;

        my $vsize = length $val;

        if ( $vsize <= $max ) {

            my @val = split //, $val;
            my $start = $#val + 1;

            # pad @val to $max
            for ( my $i = $start ; $i < $max ; $i++ ) {
                $val[$i] = ' ';
            }
            $val = join '', @val;
            substr( $val, $min - 1, $size ) = $fo_val if defined $fo_val;
            $self->{value} = $val;
        }
    }

    return $rc;
}

=pod
# VERIFY JOINS
# test for {dominant_table} & {dominant_column}
# if defined, then either set value if dominant
# or test against dominant value if not dominant
# 0 if okay
# undef if not

# status:  needs more testing and tweaking
sub handle_verify_joins {
    my $self = shift;

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my $fl       = $GlobalUi->get_field_list;

    my ( $tag, $table, $col ) = $self->get_names;
    my $dom_table = $self->{dominant_table};
    my $dom_col   = $self->{dominant_column};

    return 0 if !defined $dom_table || !defined $dom_col;

    # if this is the dominant fo, then nothing more is needed
    return 0 if $table eq $dom_table && $col eq $dom_col;

    my $fo = $fl->get_field_object( $dom_table, $tag );

    my $val     = $self->get_value;
    my $dom_val = $fo->get_value;

    $val     = '' if !defined $val;
    $dom_val = '' if !defined $dom_val;

    # invalid
    return undef if $dom_val ne $val;

    return 0;
}

# QUERYCLEAR
# should only be called from do_query
sub handle_queryclear_attribute {
    my $self = shift;

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my ( $tag, $table, $col ) = $self->get_names;

    my $screen_value = $GlobalUi->get_screen_value($tag);

    return if !defined $screen_value;

    if ( $self->{queryclear} ) {
        undef $screen_value;
        $GlobalUi->set_screen_value( $tag, '' );
    }
    return;
}
=cut

# UPSHIFT / DOWNSHIFT
sub handle_shift_attributes {
    my $self = shift;
    my $val  = shift;

    my $us = $self->{upshift};
    $val = uc($val) if defined($us);

    my $ds = $self->{downshift};
    $val = lc($val) if defined($ds);

    return $val;
}

# RIGHT
sub handle_right_attribute {
    my $self         = shift;
    my $screen_value = shift;    # complete string
    my $pos          = shift;    # cursor position in field

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my ( $tag, $table, $col ) = $self->get_names;

    my @w    = $GlobalUi->get_screen_subform_widget($tag);
    my $conf = $w[0]->{CONF};
    my $max  = $$conf{COLUMNS};                           # maximum display size

    return ( $screen_value, $pos, 0 )
      if !defined $self->{right};
    return ( $screen_value, $pos, 0 )
      if $self->{type} eq 'SERIAL';

    my @v = split //, $screen_value;

    my ( @out, $i, $vpos );
    $vpos = $#v;
    for ( $i = $max - 1 ; $i >= 0 ; $i-- ) {
        if ( $vpos >= 0 ) {
            $out[$i] = $v[$vpos];
        }
        else {
            $out[$i] = ' ';
        }
        $vpos--;
    }
    $screen_value = join '', @out;
    $GlobalUi->set_screen_value( $tag, $screen_value );

    return ( $screen_value, $pos, 0 );
}

# SUBSCRIPT
sub handle_subscript_attribute {
    my $self         = shift;
    my $screen_value = shift;    # complete string
    my $pos          = shift;    # cursor position in field

    return ( $screen_value, $pos, 0 )
      if !defined $self->{subscript_floor}
      || !defined $self->{subscript_ceiling};
    return ( $screen_value, $pos, 0 )
      if $self->{type} eq 'SERIAL';

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my $tag      = $self->get_field_tag;

    my $val   = $self->get_value;
    my $vsize = length $val;

    my $min  = $self->{subscript_floor};
    my $max  = $self->{subscript_ceiling};
    my $size = $max - $min + 1;

    if ( $vsize >= $max ) {
        $val = substr( $val, $min - 1, $size ) if defined $val;
    }
    $GlobalUi->set_screen_value( $tag, $val );
    $self->{value} = $val;    # needs to be set directly

    return ( $val, $pos, 0 );
}

# PICTURE
sub handle_picture_attribute {
    my $self = shift;
    my $val  = shift;         # one charcter at a time
    my $pos  = shift;         # cursor position in field

    # A - any letter
    # # - any number
    # X - any character

    return ( $val, $pos )
      if !defined( $self->{picture} );

    my @format = split( //, $self->{picture} );
    my $fsz = $#format;

    return ( $val, $pos, -1 )    # no more input
      if $pos > $fsz;

    my $f  = $format[$pos];
    my $t  = $self->scalar_number_or_letter($val);
    my $rc = undef;

    # lazy testing going on here...
    if ( uc $f eq '#' ) {
        $rc = -1 if ( defined $t && $t ne 'NUMBER' );
        return ( $val, $pos, $rc );
    }
    elsif ( uc $f eq 'A' ) {
        $rc = -1 if ( $t ne 'LETTER' );
        return ( $val, $pos, $rc );
    }
    elsif ( uc $f eq 'X' ) {    # just return
        return ( $val, $pos, $rc );
    }
    else {                      # jump over non-format chars
        $pos++;
        return ( $val, $pos, $rc );
    }
}

# DATE
sub handle_date_attribute {
    my $self         = shift;
    my $screen_value = shift;    # complete string
    my $pos          = shift;    # cursor position in field

    return ( $screen_value, $pos, -1 )
      if !defined $self->{format};

    my $max      = $self->{size};
    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my ( $tag, $table, $col ) = $self->get_names;

    my ( $m, $d, $y, $tmp ) = undef;
    ( $m, $d, $y ) = split /\//, $screen_value;

    return ( $screen_value, $pos, -1 )
      if !defined $m || !defined $d || !defined $y;

    my $ml = length($m);
    my $dl = length($d);
    my $yl = length($y);

    return ( $screen_value, $pos, -1 )
      if !$self->is_number($m)
      || !$self->is_number($d)
      || !$self->is_number($y);

    return ( $screen_value, $pos, -1 )
      if ( $ml == 0 || $ml > 2 )
      || ( $dl == 0 || $dl > 2 )
      || ( $yl == 0 || $yl > 4 );

    if ( uc $self->{format} eq "MM\/DD\/YYYY" ) {
        $m = '0' . $m if $ml == 1;
        $d = '0' . $d if $dl == 1;
        if ( $yl == 1 ) {
            $y = '200' . $y;
        }
        elsif ( $yl == 2 ) {
            $y = '20' . $y;
        }
        elsif ( $yl == 3 ) {
            $y = '2' . $y;
        }
        elsif ( $yl == 4 ) {
            $y = $y;
        }
        else {
            warn "something wrong with date field";
        }

        $tmp = $m . '/' . $d . '/' . $y;
        my $len = length($tmp);

        return ( $screen_value, $pos, -1 )
          if ( $len != 10 );

        $GlobalUi->set_screen_value( $tag, $tmp );
        return ( $screen_value, $pos, 0 );
    }
    if ( uc $self->{format} eq "MM\/DD\/YY" ) {
        $m = '0' . $m if $ml < 2;
        $d = '0' . $d if $ml < 2;
        $y = '0' . $y if $yl < 2;

        $tmp = $m . '/' . $d . '/' . $y;
        my $len = length($tmp);

        return ( $screen_value, $pos, -1 )
          if ( $len != 8 );

        $GlobalUi->set_screen_value( $tag, $tmp );
        return ( $screen_value, $pos, 0 );
    }
    warn "Only: MM\/DD\/YYY and MM\/DD\/YYYY date formats are supported.";
    return ( $screen_value, $pos, 0 );
}

# FORMAT
sub handle_format_attribute {
    my $self         = shift;
    my $screen_value = shift;    # complete string
    my $pos          = shift;    # cursor position in field

    my $max      = $self->{size};
    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my ( $tag, $table, $col ) = $self->get_names;

    return ( $screen_value, $pos, 0 )
      if !defined $self->{format};

    # unsupported
    return ( $screen_value, $pos, 0 )
      if $self->{type} eq 'DATETIME';
    return ( $screen_value, $pos, 0 )
      if $self->{type} eq 'INTERVAL';
    return ( $screen_value, $pos, 0 )
      if $self->{type} eq 'SERIAL';

    # FLOAT, INT and REAL

    $screen_value = $self->get_value;

    my ( $tout, $hashcnt, @vm, @vn, @fm, @fn, @tmp );
    my ( @out, @mout, @nout, $out, $mout, $nout, $i, $vpos );

    my @values = split //, $screen_value;
    my @format = split //, $self->{format};
    my $flen = length( $self->{format} );
    my $slen = length($screen_value);

    # redraw the field if re-entering it
    if ( $slen > $pos ) {
        my @stmp = split /\./, $screen_value;
        $screen_value = $stmp[0];
    }

    # get the number of "# - &"
    for ( my $i = 0 ; $i < $flen ; $i++ ) {
        my $c = $format[$i];
        $hashcnt++
          if $c eq '#'
          || $c eq '-'
          || $c eq '&';    # these chars appear in format strings in optifacts
                           # ".per" files,  but are ignored by sperform
    }

    @tmp = split /\./, $screen_value;
    if ( defined $tmp[1] ) {
        @vm = split //, $tmp[0];
        @vn = split //, $tmp[1];
    }
    else {
        @vm = split //, $tmp[0];
        @vn = ();
    }
    undef @tmp;
    @tmp = split /\./, $self->{format};
    if ( defined $tmp[1] ) {
        @fm = split //, $tmp[0];
        @fn = split //, $tmp[1];
    }
    else {
        @fm = split //, $tmp[1];
        @fn = ();
    }

    $vpos = $#vm;
    for ( $i = $#fm ; $i >= 0 ; $i-- )
    {    # treat '-' and '&' as '#' -  not clear what these chars mean
        if ( ( $fm[$i] eq '#' || $fm[$i] eq '-' || $fm[$i] eq '&' )
            && $vpos >= 0 )
        {
            my $num = $vm[$vpos];
            if ( !$self->is_number($num) ) {
                return ( $screen_value, $pos, -1 );
            }
            $mout[$i] = $num;
        }
        elsif ( ( $fm[$i] eq '#' || $fm[$i] eq '-' || $fm[$i] eq '&' )
            && $vpos < 0 )
        {
            $mout[$i] = ' ';
        }
        elsif ( $fm[$i] ne '#' && $fm[$i] ne '-' && $fm[$i] ne '&' ) {
            $mout[$i] = $fm[$i];
        }
        $vpos--;
    }

    $vpos = 0;
    for ( $i = 0 ; $i <= $#fn ; $i++ ) {
        if ( $fn[$i] eq '#' && $vpos <= $#vn ) {
            my $num = $vn[$vpos];
            if ( !$self->is_number($num) ) {
                return ( $screen_value, $pos, -1 );
            }
            $nout[$i] = $vn[$vpos];
        }
        elsif ( ( $fn[$i] eq '#' || $fn[$i] eq '-' || $fn[$i] eq '&#' )
            && $vpos > $#vn )
        {
            $nout[$i] = '0';
        }
        elsif ( $fn[$i] ne '#' || $fn[$i] ne '-' || $fn[$i] ne '&#' ) {
            $nout[$i] = $fn[$i];
        }
        $vpos++;
    }

    # calculate if too many to display
    my $fl  = length $self->{format};
    my $nfl = $fl - $hashcnt;           # number of non-numeric chars
    my $tot = $slen + $nfl;

    $mout = join '', @mout;
    $nout = join '', @nout;
    $out = $mout . '.' . $nout;

    $GlobalUi->set_screen_value( $tag, $out );
    return ( $out, $pos, 0 );

}

# FORMAT - money
# this is not a real thing.  but it may be needed insome other form
sub handle_money_attribute {
    my $self         = shift;
    my $screen_value = shift;    # complete string
    my $pos          = shift;    # cursor position in field

    return ( $screen_value, $pos, 0 )
      if !defined( $self->{money} );    # this is not real

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my ( $tag, $tbl, $col ) = $self->get_names;

    if ( $self->{db_type} eq 'MONEY' ) {
        $screen_value = '$' . $screen_value;
        $GlobalUi->set_screen_value( $tag, $screen_value );
    }
    return ( $screen_value, $pos, 0 );
}

# checks the field value against the attributes
# to determine if a sql operation is in order
# returns undef on success
# assumes nulls are "undefined"
# returns a msg on error - prepend msg to $field->{comments}
# caller must validate comments
#FIX:  maybe the return msg can be wrapped...

sub validate_input {
    my $self         = shift;
    my $screen_value = shift;
    my $mode         = shift;

    warn "TRACE: entering validate_input\n" if $::TRACE;
    my $value = $self->get_value;

    my $GlobalUi = $DBIx::Perform::GlobalUi;
    my $tag      = $self->{field_tag};
    return 0 if !$self->allows_focus($mode);

    if ( !defined($value) ) {

        # include statement with "null" set
        return 0 if defined( $self->{null_ok} );

        # REQUIRED
        if ( defined( $self->{required} ) ) {
            warn "TRACE: leaving validate_input on fail\n" if $::TRACE;
            $GlobalUi->display_error('th44s');
            $GlobalUi->change_focus_to_field_in_current_table($tag);
            return -1;
        }
        if ( !defined $self->{null_ok} ) {
            $GlobalUi->display_error('th34s');
            $GlobalUi->change_focus_to_field_in_current_table($tag);
            return -1;
        }
    }

    #INCLUDE
    if ( defined( $self->{include} ) ) {

        # INCLUDE - list of values
        my $inc_vals = $self->{include_values};
        if ( defined($inc_vals) ) {
            my $valid = $inc_vals->{ uc $value };
            if ( !$valid ) {
                $GlobalUi->display_error('th44s');
                $GlobalUi->change_focus_to_field_in_current_table($tag);
                return -1;
            }
        }

        # INCLUDE - numeric range
        my $ceiling = $self->{range_ceiling};
        my $floor   = $self->{range_floor};
        if ( defined $ceiling && defined $floor ) {

            if ( ( $value < $floor ) || ( $value > $ceiling ) ) {
                warn "TRACE: leaving validate_input on fail\n" if $::TRACE;
                $GlobalUi->display_error('th44s');
                $GlobalUi->change_focus_to_field_in_current_table($tag);
                return -1;
            }
        }
    }

=pod
    # QUERYCLEAR
    if ( defined( $self->{queryclear} ) ) {
        warn "QUERYCLEAR not supported.";
    }

    # DOMINANT TABLE/COLUMN
    if ( defined $self->{dominant_table} ) {
$self->print;
exit;
    }
=cut

    warn "TRACE: leaving validate_input on success\n" if $::TRACE;
    return 0;
}

# returns boolean if field takes a focus for an editmode
sub allows_focus {

    my $self = shift;
    my $mode = shift;

    return 0 if defined( $self->{displayonly} );
    return 0 if defined( $self->{active_tabcol} );
    return 0 if $mode eq 'add' && defined( $self->{noentry} );
    return 0 if $mode eq 'update' && defined( $self->{noupdate} );

    return 1;
}

1;

