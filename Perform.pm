
# Brenton Chapin
use 5.6.0;

package DBIx::Perform;

use strict;
use warnings;
use POSIX;
use Carp;
use Curses;    # to get KEY_*
use DBIx::Perform::DButils;
use DBIx::Perform::UserInterface;
use DBIx::Perform::SimpleList;
use DBIx::Perform::Instruct;
use base 'Exporter';
use Data::Dumper;

our $VERSION = '0.69';    # valtech: 0.69

use vars qw(@EXPORT_OK $DB $STH $STHDONE $MASTER_STH $MASTER_STHDONE );

@EXPORT_OK = qw(run);

# debug: set (unset) in runtime env
$::TRACE      = $ENV{TRACE};
$::TRACE_DATA = $ENV{TRACE_DATA};

our $GlobalUi   = new DBIx::Perform::UserInterface;
#our $MasterList = new DBIx::Perform::SimpleList;

#our $RowList	= new DBIx::Perform::SimpleList;
our $RowList = undef;
our $DB;

our $extern_name;    #name of executable with external C functions

#FIX this is off with respect to UserInterface
our %INSERT_RECALL = (
    Pg       => \&Pg_refetch,
    Informix => \&Informix_refetch,
    Oracle   => \&Oracle_refetch,
);

our %Tag_screens = ();

# 	--- runtime subs ---

sub run {
    my $fname = shift;
    $extern_name = shift;

    # can't vouch for any other than yml
    my $file_hash = $GlobalUi->parse_yml_file($fname);    # xml file
         #my $file_hash	= $GlobalUi->parse_xml_file ($fname);  # xml file
         #my $file_hash	= $GlobalUi->parse_per_file ($fname);  # per file

    $DB = DBIx::Perform::DButils::open_db( $file_hash->{'db'} );

    register_button_handlers();

    $RowList = $GlobalUi->get_current_rowlist;

    $GlobalUi->run;
}

sub register_button_handlers {

    # register the button handlers
    $GlobalUi->register_button_handler( 'query',    \&querymode );
    $GlobalUi->register_button_handler( 'next',     \&do_next );
    $GlobalUi->register_button_handler( 'previous', \&do_previous );
    $GlobalUi->register_button_handler( 'view',     \&do_view );
    $GlobalUi->register_button_handler( 'add',      \&addmode );
    $GlobalUi->register_button_handler( 'update',   \&updatemode );
    $GlobalUi->register_button_handler( 'remove',   \&removemode );
    $GlobalUi->register_button_handler( 'table',    \&do_table );
    $GlobalUi->register_button_handler( 'screen',   \&do_screen );
    $GlobalUi->register_button_handler( 'current',  \&do_current );
    $GlobalUi->register_button_handler( 'master',   \&do_master );
    $GlobalUi->register_button_handler( 'detail',   \&do_detail );
    $GlobalUi->register_button_handler( 'output',   \&do_output );
    $GlobalUi->register_button_handler( 'no',       \&do_no );
    $GlobalUi->register_button_handler( 'yes',      \&do_yes );
    $GlobalUi->register_button_handler( 'exit',     \&doquit );
}

sub clear_textfields {

    warn "TRACE: entering clear_textfields\n" if $::TRACE;

    my $fl = $GlobalUi->get_field_list;

#    my $app = $GlobalUi->{app_object};

    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my $tag = $fo->get_field_tag;
        $fo->set_value('');
        $GlobalUi->set_screen_value( $tag, '' );

#        my $scrns = get_screen_from_tag($ft);
#        foreach my $scrn (@$scrns) {
#	    my $form = $GlobalUi->get_current_form;
#            my $subform = $form->getSubform('DBForm');
#            $subform->getWidget($ft)->setField( 'VALUE', '' );
#        }

    }
    warn "TRACE: leaving clear_textfields\n" if $::TRACE;
}

sub clear_table_textfields {
    my $mode = shift;

    warn "TRACE: entering clear_textfields\n" if $::TRACE;

    my $fl = $GlobalUi->get_field_list;
    my $cur_tab = $GlobalUi->get_current_table_name;
    my $app = $GlobalUi->{app_object};
    my $joins_by_tag = $app->{joins_by_tag};

    return if $mode eq 'update';

    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my ( $tag, $table, $col ) = $fo->get_names;
	if ( $cur_tab eq $table ) {

	    next if ! $fo->allows_focus( $mode );

	    next if $mode eq 'query'				
	    && !defined $fo->{queryclear}
            && $joins_by_tag->{$tag};
#            && defined $fo->{dominant_column} # its a join 

#	    next if defined $fo->{dominant_column} # its a join 
#	    && $mode eq 'add';				

	    $fo->set_value('');
	    $GlobalUi->set_screen_value( $tag, '' );
	}
    }
    warn "TRACE: leaving clear_textfields\n" if $::TRACE;
}

#Clears the fields belonging to the detail table and not the master.
#Don't use "queryclear" attribute here.  Believe this is supposed to work
#as if queryclear is false for all the fields.
sub clear_detail_textfields {
    my $mastertbl = shift;
    my $detailtbl = shift;
    my $app = $GlobalUi->{app_object};
    my $joins_by_tag = $app->{joins_by_tag};
    my $fl = $GlobalUi->get_field_list;
    my %master;

    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my ( $tag, $table, $col ) = $fo->get_names;
        if ($joins_by_tag->{$tag}) {
            $master{$tag} = 1 if $table eq $mastertbl;
#            $detail{$tag} = 1 if $table eq $detailtbl;
        }       
    }
    
    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my ( $tag, $table, $col ) = $fo->get_names;
        if ($table eq $detailtbl && !$master{$tag}) {
	    $fo->set_value('');
	    $GlobalUi->set_screen_value( $tag, '' );
        } else {
	    my $val = $GlobalUi->get_screen_value( $tag );
	    $fo->set_value($val);
        }
    }
}


# If there are no rows, it sets DONTSWITCH and statusbars a message.
#  Returns true if no rows.
# Added check for "deletedrow", which is true if the user has deleted
# the current row.
sub check_rows_and_advise {
    my $form = shift;
    my $app  = $GlobalUi->{app_object};

    if ($app->{deletedrow}) {
        $GlobalUi->display_error('th47w');
        $form->setField( 'DONTSWITCH', 1 );
        return 1;
    }
    if ( $RowList->is_empty ) {
        my $m = $GlobalUi->{error_messages}->{'th15.'};
        $GlobalUi->display_error($m);
        $form->setField( 'DONTSWITCH', 1 );
        return 1;
    }
    return undef;
}

sub goto_screen {
    my $dest_screen = shift;
    my $app         = $GlobalUi->{app_object};

    my $fn = $app->getField('form_name');
    return 0 if ( $fn eq $dest_screen );

    #save status of source form
    my $form   = $app->getForm($fn);
    my $wid    = $form->getWidget('ModeButtons');
    my $button = $wid->getField('VALUE');
    $wid = $form->getWidget('InfoMsg');
    my $info_msg = $wid->getField('VALUE');
    $wid = $form->getWidget('ModeName');
    my $name = $wid->getField('VALUE');
    $wid = $form->getWidget('ModeLabel');
    my $label = $wid->getField('VALUE');
    my $focus = $form->getField('FOCUSED');

    $form->setField( 'EXIT',     1 );
    $app->setField( 'form_name', $dest_screen );
    warn "goto_screen: button = :$button:\n" if $::TRACE;

    #copy saved status into destination form
    $form = $app->getForm($dest_screen);
    $GlobalUi->{form_object} = $form;
    $wid = $form->getWidget('ModeButtons');
    $wid->setField( 'VALUE', $button );
    $wid = $form->getWidget('InfoMsg');
    $wid->setField( 'VALUE', $info_msg );
    $wid = $form->getWidget('ModeName');
    $wid->setField( 'VALUE', $name );
    $wid = $form->getWidget('ModeLabel');
    $wid->setField( 'X',        length $name );
    $wid->setField( 'VALUE',    $label );
    $wid->setField( 'COLUMNS',  length $label );
    $form->setField( 'FOCUSED', $focus );
    my $tbln = $GlobalUi->{current_table_number};
    $GlobalUi->update_table($tbln);

    $GlobalUi->clear_display_error;
    return 1;
}

sub goto_screen1 {
    my $rv = goto_screen('Run0');

    #    my $form = $GlobalUi->{form_object};
    #    $form->setField('FOCUSED', );
    return $rv;
}

sub next_screen {
    my $app = $GlobalUi->{app_object};

    my ( $cf, $cfa );
    $cf  = $app->getField('form_name');
    $cfa = $app->getField('form_names');
    my ($cfn) = $cf =~ /^Run(\d+)/;
    $cfn++;
    $cfn = 0 if ( $cfn >= @$cfa );
    $cf = "Run$cfn";
    return goto_screen($cf);
}

sub do_screen {
    my $app = $GlobalUi->{app_object};

    $GlobalUi->clear_comment_and_error_display;

    my $cf   = $app->getField('form_name');
    my $form = $app->getForm($cf);
    $GlobalUi->update_info_message( $form, 'screen' );
    next_screen();

    $GlobalUi->clear_display_error;
    $cf   = $app->getField('form_name');
    $form = $app->getForm($cf);
    my $row = $RowList->current_row;
    display_row( $form, $row );
    $GlobalUi->set_field_bounds_on_screen;
    $form->setField( 'DONTSWITCH', 1 );
}



# unsupported buttons

sub do_view {
    my $form = $GlobalUi->{form_object};
    $form->setField( 'DONTSWITCH', 1 );
    my $m = $GlobalUi->{error_messages}->{'th26d'};
    $GlobalUi->display_error($m);

    return undef;
}

sub do_current {
    my $form = $GlobalUi->{form_object};
    $form->setField( 'DONTSWITCH', 1 );
    my $m = $GlobalUi->{error_messages}->{'th26d'};
    $GlobalUi->display_error($m);

    return undef;
}

sub do_output {
    my $form = $GlobalUi->{form_object};
    $form->setField( 'DONTSWITCH', 1 );
    $GlobalUi->clear_comment_and_error_display;
    my $m = $GlobalUi->{error_messages}->{'th26d'};
    $GlobalUi->display_error($m);

    return undef;
}

# implemented buttons

sub do_table {
    warn "TRACE: entering do_table\n" if $::TRACE;

    my $form   = $GlobalUi->get_current_form;
    my @tables = @{ $GlobalUi->{attribute_table_names} };

    warn "Attribute tables: @tables" if $::TRACE_DATA;

    $GlobalUi->update_info_message( $form, 'table' );
    $GlobalUi->clear_comment_and_error_display;
    $form->setField( 'DONTSWITCH', 1 );

    $GlobalUi->increment_global_tablelist;
    $GlobalUi->increment_global_rowlist;

    # toggle the brackets around a field on the screen
    $GlobalUi->set_field_bounds_on_screen;

    $RowList = $GlobalUi->get_current_rowlist;
#    display_row( $form, $RowList->current_row );

    warn "TRACE: leaving do_table\n" if $::TRACE;
}

sub doquit {
    my $key  = shift;
    my $form = shift;
    my $app  = $GlobalUi->{app_object};

    $form->setField( 'EXIT', 1 );
    $app->setField( 'EXIT',  1 );
    extern_exit();
    system 'clear';
    exit;
}

sub do_yes {

    my $key  = shift;
    my $form = shift;

    my $app = $GlobalUi->{app_object};

    my %info_msgs = %{ $GlobalUi->{info_messages} };
    $GlobalUi->update_info_message( $form, $info_msgs{'yes'} );
    $GlobalUi->clear_comment_and_error_display;

    $app->draw();
    do_remove( $key, $form );

   #FIX: change focus returns to an arbitrary button and breaks on other buttons
    $GlobalUi->change_focus_to_button( $form, 'perform' );
    $GlobalUi->update_info_message( $form, $info_msgs{'query'} );
}

sub do_no {
    my $key  = shift;
    my $form = shift;

    my $app       = $GlobalUi->{app_object};
    my %info_msgs = %{ $GlobalUi->{info_messages} };

    $GlobalUi->update_info_message( $form, $info_msgs{'no'} );
    $app->draw();

   #FIX: change focus returns to an arbitrary button and breaks on other buttons
    $GlobalUi->change_focus_to_button( $form, 'perform' );
    $GlobalUi->update_info_message( $form, $info_msgs{'next'} );
}

# called from button_push with the top-level form.
sub changemode {
    my $mode        = shift;
    my $mode_resume = shift;

    my $app = $GlobalUi->{app_object};

    #my $fn = $app->getField('form_name');
    #my $form = $app->getForm($fn);
    my $form = $GlobalUi->get_current_form;

    my $subform = $form->getSubform('DBForm') || $form;
    my $fl = $GlobalUi->get_field_list;

    my $table = $GlobalUi->get_current_table_name;
    my @taborder =
      DBIx::Perform::Forms::temp_generate_taborder( $table, $mode );

    clear_table_textfields($mode);

    # change the UI mode
    $GlobalUi->change_mode_display( $form, $mode );
    $GlobalUi->update_info_message( $form, $mode );

    if ( goto_screen1() ) {
        $app->setField( 'resume_command', $mode_resume );
        return 1;
    }

    my $actkey = trigger_ctrl_blk( 'before', $mode, $table );
    return if $actkey eq "\cC";

    $app->{fresh} = 1;

    $GlobalUi->{focus} = $taborder[0];

    $subform->setField( 'TABORDER', \@taborder );
    $subform->setField( 'FOCUSED',  $taborder[0] );    # first field.
    $subform->setField( 'editmode', $mode );

    return 0;
}

sub querymode {
    warn "TRACE: entering querymode\n" if $::TRACE;

    $GlobalUi->clear_comment_and_error_display;

    warn "TRACE: leaving querymode\n" if $::TRACE;
    return if changemode( 'query', \&querymode_resume );
}

# Called as a resume entry, 'cause we have to force the form into
# the subform since we can't rely on lack of DONTSWITCH to switch there.
sub querymode_resume {
    my ($form) = @_;
    querymode(@_);
    $form->setField( 'FOCUSED', 'DBForm' );
}

sub do_master {
    warn "TRACE: entering do_master\n" if $::TRACE;

    my $app  = $GlobalUi->{app_object};
    my $form = $GlobalUi->get_current_form;

    $GlobalUi->update_info_message( $form, 'master' );
    $GlobalUi->clear_comment_and_error_display;
    $form->setField( 'DONTSWITCH', 1 );

    my ( $master, $detail );
    my $ct = $GlobalUi->get_current_table_name;
    my ( $m, $d ) = $GlobalUi->get_master_detail_table_names($ct);

    my @masters = @$m;
    $master = $masters[0];
    my @details = @$d;
    $detail = $details[0];

    if ( $ct eq $detail ) {       # switch to master from detail
        if ( my $tb = $GlobalUi->go_to_table($master) ) {

            $GlobalUi->update_info_message( $form, 'master' );
            $GlobalUi->clear_comment_and_error_display;
            $form->setField( 'DONTSWITCH', 1 );

            # toggle the brackets around a field on the screen
            $GlobalUi->set_field_bounds_on_screen;

            $RowList = $GlobalUi->get_current_rowlist;
            display_row( $form, $RowList->current_row );
            warn "TRACE: leaving do_master\n" if $::TRACE;
            return;
        }
        warn "TRACE: leaving do_master\n" if $::TRACE;
        die "something wrong with do_master";
    }

    $form->setField( 'DONTSWITCH', 1 );
    my $msg = $GlobalUi->{error_messages}->{'no47.'};
    $GlobalUi->display_error($msg);
    warn "TRACE: leaving do_master\n" if $::TRACE;
    return undef;
}

# . switches to the detail table if in a master table
#   and does a query
# . sends a status message if current table isn't a detail

sub do_detail {
    warn "TRACE: entering do_detail\n" if $::TRACE;

    my $app     = $GlobalUi->{app_object};
    my $form    = $GlobalUi->get_current_form;
    my $subform = $form->getSubform('DBForm') || $form;

    $GlobalUi->update_info_message( $form, 'detail' );
    $GlobalUi->clear_comment_and_error_display;
    $form->setField( 'DONTSWITCH', 1 );

    my $ct = $GlobalUi->get_current_table_name;
    my ( $m, $d ) = $GlobalUi->get_master_detail_table_names($ct);

    my @masters = @$m;
    my @details = @$d;
    my ( $master, $detail );

    if ( $#masters > 0 ) {
        $master = $masters[1];
        $detail = $details[1];
    }
    else {
        $master = $masters[0];
        $detail = $details[0];
    }

    if ( $ct eq $master ) {       # switch to detail from master
        if ( my $tb = $GlobalUi->go_to_table($detail) ) {

            $GlobalUi->update_info_message( $form, 'master' );
            $GlobalUi->clear_comment_and_error_display;
            $form->setField( 'DONTSWITCH', 1 );

            # toggle the brackets around a field on the screen
            $GlobalUi->set_field_bounds_on_screen;

            $RowList = $GlobalUi->get_current_rowlist;
#            display_row( $form, $RowList->current_row );

            clear_detail_textfields($master, $detail);
            do_query( "nop", "nop", $subform );

            warn "TRACE: leaving do_detail\n" if $::TRACE;
            return;
        }
        warn "TRACE: leaving do_detail\n" if $::TRACE;
        die "something wrong with do_detail";
    }

    $form->setField( 'DONTSWITCH', 1 );
    my $msg = $GlobalUi->{error_messages}->{'no48.'};
    $GlobalUi->display_error($msg);
    warn "TRACE: leaving do_detail\n" if $::TRACE;
    return undef;
}

sub do_previous {
    my $key  = shift;
    my $form = shift;
    my $app  = $GlobalUi->{app_object};

    $GlobalUi->update_info_message( $form, 'previous' );
    $GlobalUi->clear_comment_and_error_display;
    $form->setField( 'DONTSWITCH', 1 );
    $GlobalUi->clear_display_error;

    if ( $RowList->is_empty ) {
        $GlobalUi->display_error('no16.');
        $app->{deletedrow} = 0;
        return;
    }
    if ( $RowList->is_first ) {
        my $row = $RowList->current_row;
        display_row( $form, $row );

        # at the end of the list, switch to "Previous" button
        $form->getWidget('ModeButtons')->setField( 'VALUE', 2 );
        $GlobalUi->display_error('no41.');
        $GlobalUi->update_info_message( $form, 'previous' );
        return unless $app->{deletedrow};
    }
    my $distance = $app->{'number'};
    $distance = 1 unless $distance;
    $app->{deletedrow} = 0;

    # Perform counts down from the most recent fetch - don't know why
    my $row = $RowList->previous_row($distance);
    display_row( $form, $row );

    return $row;
}

sub do_next {
    my $key  = shift;
    my $form = shift;
    my $app  = $GlobalUi->{app_object};

    $GlobalUi->update_info_message( $form, 'next' );
    $GlobalUi->clear_display_error;
    $form->setField( 'DONTSWITCH', 1 );
    $GlobalUi->clear_display_error;

    if ( $RowList->is_empty ) {
        $GlobalUi->display_error('no16.');
        $app->{deletedrow} = 0;
        return;
    }
    if ( $RowList->is_last ) {
        my $row = $RowList->current_row;
        display_row( $form, $row );

        # at the end of the list, switch to "Next" button
        $form->getWidget('ModeButtons')->setField( 'VALUE', 1 );
        $GlobalUi->display_error('no41.');
        $GlobalUi->update_info_message( $form, 'next' );
        return unless $app->{deletedrow};
    }
    my $distance = $app->{'number'};
    $distance = 1 unless $distance;
    $distance = 0 if $app->{deletedrow};
    $app->{deletedrow} = 0;

    # Perform counts down from the most recent fetch (up for prev)
    my $row = $RowList->next_row($distance);
    display_row( $form, $row );

    return $row;
}

sub addmode {
    warn "TRACE: entering addmode\n" if $::TRACE;
    return if changemode( 'add', \&addmode_resume );

    my $form    = $GlobalUi->get_current_form;
    my $subform = $form->getSubform('DBForm') || $form;
    my $fl      = $GlobalUi->get_field_list;

    $GlobalUi->clear_comment_and_error_display;

    # initalize any serial or default fields to screen
    $fl->display_defaults_to_screen($GlobalUi);

    warn "TRACE: leaving addmode\n" if $::TRACE;
    return undef;
}

sub addmode_resume {
    my $subform = shift;
    addmode(@_);
    $subform->setField( 'FOCUSED', 'DBForm' );
}

sub updatemode {
    my $form = $GlobalUi->get_current_form;

    $GlobalUi->update_info_message( $form, 'update' );
    return if check_rows_and_advise($form);

    return if changemode( 'update', \&updatemode_resume );

    $GlobalUi->clear_comment_and_error_display;

    my $subform = $form->getSubform('DBForm');
    my $fl      = $GlobalUi->get_field_list;

    my $row = $RowList->current_row;

    $fl->reset;
    while ( my $f = $fl->iterate_list ) {
        my ( $ft, $tbl, $col ) = $f->get_names;
        my $w = $subform->getWidget($ft);
        next unless $col;
    }
}

sub updatemode_resume {
    my ($form) = @_;
    updatemode(@_);
    $form->setField( 'FOCUSED', 'DBForm' );
}

# sub edit_control  #replaced with Perform::Instruct::trigger_ctrl_blk

sub removemode {
    my $key  = shift;
    my $form = shift;

    my %info_msgs = %{ $GlobalUi->{info_messages} };
    my %err_msgs  = %{ $GlobalUi->{error_messages} };
    my @buttons   = $GlobalUi->{buttons_yn};
    my $app       = $GlobalUi->{app_object};

    $GlobalUi->update_info_message( $form, 'remove' );
    $form->setField( 'DONTSWITCH', 1 );
    $GlobalUi->clear_comment_and_error_display;

    if ( $RowList->is_empty ) {

        #my $m  = $err_msgs{'th15.'};
        #$GlobalUi->display_error($m);
        $GlobalUi->display_error( $err_msgs{'th15.'} );
        return;
    }
    if ($app->{deletedrow}) {
        $GlobalUi->display_error('th47w');
        return;
    }

    #'before remove' only works on tables.  Don't believe it makes any
    # sense to trigger off a column-- the smallest element that can be
    # removed is 1 row.
    my $table = $GlobalUi->get_current_table_name;
    my $actkey = trigger_ctrl_blk( 'before', 'remove', $table );
    return if $actkey eq "\cC";

    $GlobalUi->update_info_message( $form, $info_msgs{'no'} );
    $GlobalUi->switch_buttons( $form, 'REMOVE', @buttons );
}

sub do_remove {

    #my $key = shift;
    #my $form = shift;

    warn "TRACE: entering do_remove\n" if $::TRACE;

    my $app  = $GlobalUi->{app_object};
    my $form = $GlobalUi->get_current_form;

    return if check_rows_and_advise($form);

    my $table = $GlobalUi->get_current_table_name;

    my $subform = $form->getSubform('DBForm');
    my $fl      = $GlobalUi->get_field_list;

    my @wheres = ();
    my @values = ();

    my $row     = $RowList->current_row;
    my $aliases = $app->{'aliases'};

    my $ralias = $aliases->{"$table.rowid"};
    my $wheres = "rowid = $$row{$ralias}";
    my $cmd    = "delete from $table where $wheres";

    warn "Remove command:\n$cmd\n" if $::TRACE_DATA;
    my $rc = $DB->do( $cmd, {}, @values );
    if ( !defined $rc ) {
        my $m1 = $GlobalUi->{error_messages}->{'da11r'};
        my $m2 = ": $DBI::errstr";
        $GlobalUi->display_comment($m1);
        $GlobalUi->display_error($m2);
    }
    else {
        my $msg = "Row removed.";
        $RowList->remove_row;
        clear_textfields();
        $app->{deletedrow} = 1;
    }
    trigger_ctrl_blk( 'after', 'remove', $table );
    $form->setField( 'DONTSWITCH', 1 );    # in all cases.

    warn "TRACE: exiting do_remove\n" if $::TRACE;
}

sub OnFieldEnter {
    my ( $status_bar, $field_tag, $subform, $key ) = @_;

    warn "TRACE: entering OnFieldEnter\n" if $::TRACE;
    &$status_bar                          if ($status_bar);

    my $app   = $GlobalUi->{app_object};
    my $form  = $GlobalUi->get_current_form;
    my $fl    = $GlobalUi->get_field_list;
    my $table = $GlobalUi->get_current_table_name;


    my $fo = $fl->get_field_object( $table, $field_tag );
    die "undefined field object" unless defined($fo);

    my $comment = $fo->{comments};
    $comment
      ? $GlobalUi->display_comment($comment)
      : $GlobalUi->clear_display_comment;

    my $widget = $subform->getWidget($field_tag);
    $widget->{CONF}->{'EXIT'} = 0;

    # do any BEFORE control blocks.
    my $mode = $subform->getField('editmode');
    my $actkey = trigger_ctrl_blk_fld( 'before', "edit$mode", $fo );

    bail_out() if ( $actkey eq "\cC" );    # 3 is ASCII code for ctrl-c

    warn "TRACE: leaving OnFieldEnter\n" if $::TRACE;
}

sub OnFieldExit {
    my ( $field_tag, $subform, $key ) = @_;

    warn "TRACE: entering OnFieldExit\n" if $::TRACE;

    my $app    = $GlobalUi->{app_object};
    my $form   = $GlobalUi->get_current_form;
    my $fl     = $GlobalUi->get_field_list;
    my $table  = $GlobalUi->get_current_table_name;
    my $fo     = $fl->get_field_object( $table, $field_tag );
    my $widget = $subform->getWidget($field_tag);
    my $mode   = $subform->getField('editmode');

    # erase comments and error messages
    $GlobalUi->clear_comment_and_error_display;

    if ( $key eq "\cp" ) {
        my $aliases = $app->{'aliases'};
        my $row     = $RowList->current_row;
        my ( $tag, $tbl, $col ) = $fo->get_names;
        my $tnc   = "$tbl.$col";
        my $alias = $aliases->{$tnc};
        my $val = $row->{$alias};
        my ( $pos, $rc );
#warn "ctrl-p: $tag = $val\n";
        ( $val, $pos, $rc ) = $fo->format_value_for_display( $val, 0 );
        $GlobalUi->set_screen_value( $tag, $val );
    }

    if ($mode ne "query") {
        my $good = 1;
        my $val = $GlobalUi->get_screen_value($field_tag);
        $good = 0 if ($fo->validate_input($val, $mode) < 0);
        if ($good && $fo->is_any_numeric_db_type) {
            if ($val ne '' && !$fo->is_number($val)) {
                $GlobalUi->display_error('er11d');
                $good =  0;
            }
        }
        $good = 0 if ($good && !verify_joins($table, $field_tag));
        if (!$good) {
            $GlobalUi->{'newfocus'} = $GlobalUi->{'focus'}
              unless $GlobalUi->{'newfocus'};
        }
    }

    trigger_lookup($field_tag);

    my $actkey = trigger_ctrl_blk_fld( 'after', "edit$mode", $fo );
    my $value = $fo->get_value;
    $key = $actkey if !defined $key || $actkey ne "\c0";
    warn "key: [" . unpack( 'U*', $key ) . "]\n" if $::TRACE;

    $subform->setField( 'DONTSWITCH', 0 );
    if (
        $key    eq "\t"    # advance to the next field
        || $key eq "\n" 
        || $key eq KEY_DOWN || $key eq KEY_RIGHT
      )
    {

        #	$GlobalUi->clear_comment_and_error_display;
        return;
    }

    my $dontswitch = 1;

    if ( $key eq "\c[" ) {
        my $wid = $form->getWidget('ModeButtons');
        my $mode =
          lc( ( $wid->getField('LABELS') )->[ $wid->getField('VALUE') ] );
        my $modesubs = $GlobalUi->{mode_subs};
        my $sub      = $modesubs->{$mode};       # mode subroutine

        if ( $sub && ref($sub) eq 'CODE' ) {
            $dontswitch = 0;                     # let the sub decide.
            &$sub( $field_tag, $widget, $subform )
              ;                                  # call the mode "do_add" etc..
        }
        else {
            beep();
        }
    }
    elsif ( $key eq "\cw" ) {
        $GlobalUi->display_help_screen('field');
        $GlobalUi->{'newfocus'} = $GlobalUi->{'focus'}
          unless $GlobalUi->{'newfocus'};
        return;
    }
    elsif ( $key eq "\cC" )                      # Ctrl-C
    {
        bail_out();
    }
    elsif ($key eq "\cK"
        || $key eq KEY_UP
        || $key eq KEY_LEFT
        || $key eq KEY_BACKSPACE
        || $key eq KEY_STAB )
    {
        my $ct   = $GlobalUi->get_current_table_name;
        my $mode = $subform->getField('editmode');

        my @taborder =
          DBIx::Perform::Forms::temp_generate_taborder( $ct, $mode );
        my %taborder = map { ( $taborder[$_], $_ ) } ( 0 .. $#taborder );
        my $i = $taborder{ $GlobalUi->{'focus'} };
        $i = ( $i <= 0 ) ? $#taborder : $i - 1;

        $subform->setField( 'FOCUSED', $taborder[$i] );
        $GlobalUi->{'newfocus'} = $taborder[$i]
          unless $GlobalUi->{'newfocus'};

#        $GlobalUi->clear_comment_and_error_display;

        return;
    }
    elsif ( $key eq "\cF" ) {
        my $ct   = $GlobalUi->get_current_table_name;
        my $mode = $subform->getField('editmode');
        my @taborder =
          DBIx::Perform::Forms::temp_generate_taborder( $ct, $mode );
        my %taborder  = map { ( $taborder[$_], $_ ) } ( 0 .. $#taborder );
        my $i         = $taborder{ $GlobalUi->{'focus'} };
        my $w         = $subform->getWidget( $taborder[$i] );
        my $y_cur     = $w->getField('Y');
        my $y         = $y_cur;
        my $screenpad = 0;
        my $limit     = @taborder + 0;
        do {
            $i = ( $i >= $#taborder ) ? 0 : $i + 1;
            my ( $cf, $cfa, $cfn );
            $cf  = $app->getField('form_name');
            $cfa = $app->getField('form_names');
            ($cfn) = $cf =~ /^Run(\d+)/;
            my $limit2 = @$cfa + 0;
            do {
                $w = $subform->getWidget( $taborder[$i] );
                unless ( defined $w ) {
                    $cfn++;
                    $cfn = 0 if ( $cfn >= @$cfa );
                    $cf = "Run$cfn";
                    my $form = $app->getForm($cf);
                    $subform = $form->getSubform('DBForm');
                    $screenpad += $y_cur + 1;
                }
                $limit2--;
            } while ( !( defined $w ) && $limit2 >= 0 );
            $limit--;
            $y = $w->getField('Y') + $screenpad;
        } while ( $y <= $y_cur && $limit >= 0 );
        $i = $taborder{ $GlobalUi->{'focus'} } unless $limit >= 0;
        $GlobalUi->{'newfocus'} = $taborder[$i]
          unless $GlobalUi->{'newfocus'};
    }
    elsif ( $key eq "\cB" ) {
        my $ct   = $GlobalUi->get_current_table_name;
        my $mode = $subform->getField('editmode');
        my @taborder =
          DBIx::Perform::Forms::temp_generate_taborder( $ct, $mode );
        my %taborder  = map { ( $taborder[$_], $_ ) } ( 0 .. $#taborder );
        my $i         = $taborder{ $GlobalUi->{'focus'} };
        my $w         = $subform->getWidget( $taborder[$i] );
        my $y_cur     = $w->getField('Y');
        my $y         = $y_cur;
        my $screenpad = 0;
        my $limit     = @taborder + 0;
        do {
            $i = ( $i <= 0 ) ? $#taborder : $i - 1;
            my ( $cf, $cfa, $cfn );
            $cf  = $app->getField('form_name');
            $cfa = $app->getField('form_names');
            ($cfn) = $cf =~ /^Run(\d+)/;
            my $limit2 = @$cfa + 0;
            do {
                $w = $subform->getWidget( $taborder[$i] );
                unless ( defined $w ) {
                    $cfn--;
                    $cfn = $#$cfa if ( $cfn < 0 );
                    $cf = "Run$cfn";
                    my $form = $app->getForm($cf);
                    $subform = $form->getSubform('DBForm');
                    $screenpad -= 256;    #FIX -- can't guarantee < 256 lines
                }
                $limit2--;
            } while ( !( defined $w ) && $limit2 >= 0 );
            $limit--;
            $y = $w->getField('Y') + $screenpad;
        } while ( $y >= $y_cur && $limit >= 0 );
        $i = $taborder{ $GlobalUi->{'focus'} } unless $limit >= 0;
        $GlobalUi->{'newfocus'} = $taborder[$i]
          unless $GlobalUi->{'newfocus'};
    }

    if ($dontswitch) {
        $subform->setField( 'DONTSWITCH', 1 );
    }

    warn "TRACE: leaving OnFieldExit\n" if $::TRACE;
}

sub bail_out {
    warn "TRACE: entering bail_out\n" if $::TRACE;
    my $app     = $GlobalUi->{app_object};
    my $form    = $GlobalUi->get_current_form;
    my $subform = $form->getSubform('DBForm');

    # Bailing out of Query, Add, Update or Modify.
    # Re-display the row as it was, if any.
    if ( $RowList->not_empty ) {
        display_row( $subform, $RowList->current_row );
    }
#    else {
#        clear_textfields();
#    }

    # Back to top menu
    $GlobalUi->clear_comment_and_error_display;

    $form->setField( 'DONTSWITCH', 0 );
    $subform->setField( 'EXIT',    1 );

    my $wname = $subform->getField('FOCUSED');
    my $wid   = $subform->getWidget($wname);
    $wid->{CONF}->{'EXIT'} = 1;
    $GlobalUi->change_mode_display( $subform, 'perform' );
}

#if the given field joins columns, and one of those other than the given
#table.column has "*", then must do a query.
#If the result of the query is that the current value is not in that
#other table.column, then the input must be rejected and the cursor
#kept in the field.
sub verify_joins {
    my $t = shift;
    my $f = shift;
warn "TRACE: entering verify_joins for field $f, table $t\n" if $::TRACE;
    my $fl  = $GlobalUi->get_field_list;
    my $fos = $fl->get_fields_by_field_tag($f);
    for (my $i = $#$fos; $i >= 0; $i--) {
        if ($$fos[$i]->{verify}) {
            my $dt = $$fos[$i]->{table_name};
            my $dc = $$fos[$i]->{column_name};
            return verify_join($f, $dt, $dc);
        }
        my $luh = $$fos[$i]->{lookup_hash};
        foreach my $n (keys %$luh) {
            my $lus = $luh->{$n};
            foreach my $lu (keys %$lus) {
                if ($lus->{$lu}->{verify}) {
                    my $dt = $lus->{$lu}->{join_table};
                    my $dc = $lus->{$lu}->{join_column};
                    return verify_join($f, $dt, $dc);
                }
            }
        }
    }
    return 1;
}

sub verify_join {
    my ($f, $dt, $dc) = @_;

    my $val = $GlobalUi->get_screen_value($f);
    my $query = "select $dt.$dc from $dt"
              . "\nwhere $dt.$dc = ?";
warn "verify_join\n$query\n$val\n" if $::TRACE;

    my $sth = $DB->prepare($query);
    warn "$DBI::errstr\n" unless $sth;
    $sth->execute(($val));
    my $ref = $sth->fetchrow_array;
    return 1 if $ref;
    $GlobalUi->display_error(" This is an invalid value --"
       . " it does not exist in \"$dt\" table ");
    return 0;
}

sub verify_composite_joins {
    my $app = $GlobalUi->{app_object};
    my $instrs = $app->getField('instrs');
    my $composites = $instrs->{COMPOSITES};

    if (defined $composites) {
        my $current_tbl = $GlobalUi->get_current_table_name;
        my $fl          = $GlobalUi->get_field_list;
        foreach my $co (@$composites) {
            if (   $co->{TBL1} eq $current_tbl
                || $co->{TBL2} eq $current_tbl) {
                my $tbln = 1;
                $tbln = 2 if $co->{VFY2} eq '*';
                my $tbl = $co->{"TBL$tbln"};

                my %wheres;
                my $col;
                for (my $i = 0; $i < @{$co->{COLS1}}; $i++ ) {
                    $col = $co->{"COLS$tbln"}[$i];
                    my $flds = $fl->get_fields_by_table_and_column($tbl, $col);
                    my $val =
                      $GlobalUi->get_screen_value($$flds[0]->{field_tag});
                    $wheres{"$tbl.$col = ?"} = $val;
                }

                my $query = "select $tbl.$col\nfrom $tbl\nwhere\n"
                  . join ("\nand ", keys %wheres);
warn "verify_composite_joins:\n$query\n"
     . join (", ", values %wheres) . "\n" if $::TRACE;

                my $sth = $DB->prepare($query);
                warn "$DBI::errstr\n" unless $sth;
                $sth->execute(values %wheres);
                my $ref = $sth->fetchrow_array;
                return 1 if $ref;

                $GlobalUi->display_error(" Invalid value -- its composite "
                  . "value does not exist in \"$tbl\" table ");
                return 0;
            }
        }       
    }
    return 1;
}

# this sub is for debugging only
#sub temp_which_subform_are_we_in
#{
#    my $sf = shift;
#    my $app	= $GlobalUi->{app_object};
#    my ($cfn, $cfa);
#    $cfa = $app->getField('form_names');
#    for ($cfn = 0; $cfn < @$cfa; $cfn++) {
#        my $cf = "Run$cfn";
#        my $form = $app->getForm($cf);
#        my $subform = $form->getSubform('DBForm');
#        return $cfn if ($subform == $sf);
#    }
#    return -1;
#}

#sub temp_get_screen_from_tag
#{
#    my $tag = shift;
#    my $app = $GlobalUi->{app_object};
#
#    my ($cfn, $cfa);
#    $cfa = $app->getField('form_names');
#    for ($cfn = 0; $cfn < @$cfa; $cfn++) {
#        my $cf = "Run$cfn";
#        my $form = $app->getForm($cf);
#        my $subform = $form->getSubform('DBForm');
#        return $cfn if (defined $subform->getWidget($tag));
#    }
#    return -1;
#}


sub get_screen_from_tag {
    my $tag = shift;

    unless ( defined $Tag_screens{$tag} ) {
        my @scrns = ();
        my $app   = $GlobalUi->{app_object};
        my ( $cfn, $cfa );
        $cfa = $app->getField('form_names');
        for ( $cfn = 0 ; $cfn < @$cfa ; $cfn++ ) {
            my $cf      = "Run$cfn";
            my $form    = $app->getForm($cf);
            my $subform = $form->getSubform('DBForm');
            if ( defined $subform->getWidget($tag) ) {
                push @scrns, $cfn;
            }
        }
        $Tag_screens{$tag} = \@scrns;
    }
    return $Tag_screens{$tag};
}

#sub get_value_from_tag {
#    my $field_tag = shift;
#
#    my $fl    = $GlobalUi->get_field_list;
#    my $fo = get_field_object_from_tag($field_tag);
#    my $rv;
#    $rv = $fo->get_value if defined $fo;
##warn "get_value_from_tag: $rv field = :$field_tag:\n";
#    return $rv;
#}

sub get_field_object_from_tag {
    my $ft = shift;
    my $fl = $GlobalUi->get_field_list;

    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        if ( $fo->{field_tag} eq $ft ) {
            return $fo;
        }
    }
    return undef;
}

#Lookups always go with a join.  Given a line in a .per script:
#  f1 = t1.c1 lookup f2 = t2.c2 joining t2.c1
#We fill f2 with t2.c2 from those rows of t2 in which t1.c1 = t2.c1
#We fill immediately whenever the value in f1 changes.
#Not certain what should happen if c1 has duplicate values.
#active_tabcol = t1.c1,  join_table = t2, join_column = t2.c1
sub trigger_lookup {
    my $trigger_tag = shift;
    warn "TRACE: entering trigger_lookup for $trigger_tag\n" if $::TRACE;
    my $app = $GlobalUi->{app_object};
#    my $f1o = get_field_object_from_tag($trigger_tag);
    my $tval = $GlobalUi->get_screen_value($trigger_tag);
    my $fl   = $GlobalUi->get_field_list;
    my $fos = $fl->get_fields_by_field_tag($trigger_tag);

    foreach my $f1o (@$fos) { 
        my ( $f1, $t1, $c1 ) = $f1o->get_names;
        my $tnc  = "$t1.$c1";

        $fl->reset;
        while ( my $fo = $fl->iterate_list ) {
            if ( defined $fo->{active_tabcol} 
                 && $fo->{active_tabcol} eq $tnc ) {
                my $val;
                my $t2 = $fo->{join_table};
                my $c2 = $fo->{join_column};
                my ( $tag, $tbl, $col ) = $fo->get_names;
                if ( defined $tval && $tval ne '' ) {
                    my %tbls;
                    $tbls{$t1} = 1;
                    $tbls{$t2} = 1;
                    $tbls{$tbl} = 1;
                    my $query =
                        "select $tbl.$col from " . join (', ', keys %tbls)
                      . " where $tnc = $t2.$c2"
                      . " and $tnc = ?";
                    my $sth = $DB->prepare($query);
                    warn "$DBI::errstr\n" unless $sth;
                    $sth->execute(($tval));
                    $val = $sth->fetchrow_array;
                    warn "query = $query\nval = $tval\n" if $::TRACE;
                    warn "tag = :$tag: result of query = :$val:\n"
                        if defined $val && $::TRACE;
                }
                else {
                    $val = '';
                }
                $fo->set_value($val);
                $app->{redraw_subform} = 1;
                my ( $pos, $rc );
                ( $val, $pos, $rc ) = $fo->format_value_for_display( $val, 0 );
                $GlobalUi->set_screen_value( $tag, $val );
            }
        }
    }
}

#Complicated queries are tricky to get right.  A perfectly valid query
# may be unacceptably slow.  Given 3 tables, t1, t2, and t3, each with
# columns mca, mcb, ca, cb where mca and mcb are "matching columns"
# (t1.mca = t2.mca) and t1.ca is unrelated to t2.ca and so on, we
# want every row from t1, with 1 matching row (if any) from t2 and t3.
# We have to use some means of getting just 1 row from t2 and t3 per row
# from t1.  Speaking of just t1 and t2, an inner join will leave out a row
# from t1 if no rows in t2 match that row.  An outer join will have 2 or
# more rows in the results if more than 1 row of t2 matches a single row
# of t1.  So, neither delivered the desired results.  (Just why sperform
# works that way is another question that doesn't seem to have a good
# answer.)  An answer to this problem was to use a function that would
# return just one row of t2 per row of t1, such as "min".  The query then
# became:
#
# select min(t2.ca) aa, min(t2.cb) ab, t1.ca ac, t1.cb ad
# from t1, outer t2 where t1.mca = t2.mca
# group by t1.ca, t1.cb
#
# This worked except when t1 had duplicate rows.  However, when t3 is
# thrown in the mix, and we join the tables with a relation between t2
# and t3, then we have trouble.  The query below might be extremely slow,
# taking many hours to run:
#
# select min(t2.ca) aa, min(t2.cb) ab, t1.c2 ac, t1.c3 ad,
#        min(t3.ca) ae, min(t3.cb) af, t1.mca ag, min(t2.mcb) ah
#   from t1, outer t2, t3 where t1.mca = t2.mca and t2.mcb = t3.mcb
#   group by t1.c2, t1.c3, t1.mca
#
# As long as all the joins are between t1 and the other tables, the query
# is fast.  To handle the situation when they're not, needed to work out
# another query formulation.  Doing it in 2 queries with a temporary table
# works:
#
# select min(t2.ca) aa, min(t2.cb) ab, t1.ca ac, t1.cb ad,
#        t1.mca ae, min(t2.mcb) af
#   from t1, outer t2 where t1.mca = t2.mca
#   group by t1.ca, t1.cb into temp tmpperl;
# select tmpperl.aa aa, tmpperl.ab ab, tmpperl.ac ac, tmpperl.ad ad,
#        tmpperl.ae ae, min(t3.ca) af, min(t3.cb) ag
#   from tmpperl, outer t3
#   where tmpperl.af = t3.mcb

# Take 6:  Query is still not good enough.
# At least 2 problems:  
# 1. The minimum value of each column may be in different rows,
# and if min is used on more than one col, we want everything to be from
# the same row.
# 2. In a lookup, the form may ask for the same column in more than one place,
# with different conditions.

# Take 7:  The query strategy had to change some more.
# The strategy used in take5 could get columns from different rows of
# joined tables, because all it did was get the minimum of each column
# regardless of what rows the minimums of any other columns came from.
# This version replaces the single query for those minimums with 2.
# The 1st of the 2 queries gets only the minimum rowid.  Then the 2nd does
# not use minimum at all but instead gets the rest of the columns from
# the joined table with "where joined.rowid = pf_tmpx.row_id".

#Make a graph of all the joins.
#  (Each node represents a table, and each edge represents a join.)
sub compute_joins {
    my (%joins, %tags);
    my $fl = $GlobalUi->get_field_list;
    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my ( $tag, $tbl, $col ) = $fo->get_names;
#get joins in lookups
        if ($fo->{active_tabcol}) {
            my $t2 = $fo->{join_table};
            my $c2 = $fo->{join_column};
            my ( $t1, $c1 ) = $fo->{active_tabcol} =~ /(\w+)\.(\w+)/;
            if ($t1 ne $t2) {
                $joins{$t1}->{$t2}->{"$c1 $c2 $tag"} = 1;
                $joins{$t2}->{$t1}->{"$c2 $c1 $tag"} = 1;
            }
        }
#get all other joins
        if ( defined $tags{$tag} ) {
            foreach my $jtag (keys %{$tags{$tag}}) {
                my ( $t1, $c1 ) = $jtag =~ /(\w+)\.(\w+)/;
                if ($t1 ne $tbl) {
                    $joins{$t1}->{$tbl}->{"$c1 $col"} = 1;
                    $joins{$tbl}->{$t1}->{"$col $c1"} = 1;
                }
            }
        }
        $tags{$tag}->{"$tbl.$col"} = 1;
    }
    return %joins;
}

sub get_query_conditions {
    my $qtbl = shift;
    my %wheres;

    my $fl = $GlobalUi->get_field_list;
    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        next if $fo->{displayonly};
        my ( $tag, $tbl, $col ) = $fo->get_names;
        if ($qtbl eq $tbl) {
            my $val = $GlobalUi->get_screen_value($tag);
            $val = $fo->get_value if $fo->{right};
            if ( defined $val && $val ne '') {
                my ( $wexpr, $wv ) = query_condition( $tbl, $col, $val );
                $wheres{$wexpr} = \@$wv;
            }
        }
    }
    return %wheres;
}

#input is an array of "tbl.col" strings.
#output is an array of "tbl.col alias" strings.
sub append_aliases {
    my %tncs = @_;
    my $fl      = $GlobalUi->get_field_list;
    my $app     = $GlobalUi->{app_object};
    my $aliases = $app->{aliases};
    my %hash;

    my %aliased;
    foreach my $tnc (keys %tncs) {
        if (! $hash{$tnc}) {
            my ($t, $c) = $tnc =~ /(\w+)\.(\w+)/;
            my $flds = $fl->get_fields_by_table_and_column($t, $c);
            my $alias = $aliases->{$tnc};
            if (@$flds > 1) {
                my $i;
                for ($i = 0; $i < @$flds; $i++) {
                    my $fo = @$flds[$i];
                    my ( $tag, $tbl, $col ) = $fo->get_names;
                    $alias = $aliases->{"$tnc $tag"};
                    $aliased{"$tnc $alias"} = 1;
                }
            } else {
                $aliased{"$tnc $alias"} = 1;
            }
            $hash{$tnc} = 1;
        }
    }    

    return %aliased;
}

#input is a "table" and an array of "col" strings.
#output is an array of "tbl.col alias" strings.
sub prepend_table_name {
    my $tbl = shift;
    my %cs = @_;
    my %tncs;

    foreach my $c (keys %cs) {
        $tncs{"$tbl.$c"} = 1;
    }
    return %tncs;
}

#sub do_query_take7 {
sub do_query {
    my ( $field, $widget, $subform ) = @_;
    my $TMPTBL       = "pf_tmp";
    my $tmptn = 1;                              #temp table number
    my $tmptlun = 0;                    #temp table number for lookups
    my (%tbl_visit, %tbl_prev_visit, %tbl_cur_visit, %tbl_next_visit);
    my $more;
    my $current_tbl = $GlobalUi->get_current_table_name;
    my $app         = $GlobalUi->{app_object};
    my $query;
    my @queries = ();
    my $sth;
    
    generate_query_aliases();
    my $aliases = $app->{'aliases'};
    my %joins = compute_joins;

#warn Data::Dumper->Dump([%lookups], ['lookups']);


#first query    
    my %wheres = get_query_conditions($current_tbl);
    my $fl = $GlobalUi->get_field_list;
    my @colsa = $fl->get_columns($current_tbl);
    my %cols;
    map { $cols{$_} = 1; } @colsa;
    $cols{rowid} = 1;

    my %tncs = prepend_table_name($current_tbl, %cols);
    my %selects = append_aliases(%tncs);


    $query = "select\n" . join (",\n", keys %selects)
           . "\nfrom $current_tbl";
    $query .= "\nwhere\n" . join ("\nand ", keys %wheres) if %wheres;
    my @vals;
    foreach my $val (values %wheres) {
        push @vals, @$val;
    }


    my @tables = ("$TMPTBL$tmptn");
    my %tblsintmp;
    $tblsintmp{$current_tbl} = 1;
    my @outertbls = keys %{$joins{$current_tbl}};
    $more = @outertbls;



#Starting with $current_table, follow the joins as in a breadth first search.
#The number of queries needed is 1 + 2x the depth of the search + lookups.
    while ($more) {
        $query .= "\ninto temp $TMPTBL$tmptn";

#do the query for the rowid, and put the results into a temporary table
warn "$query;\n" if $::TRACE;

        push @queries, $query;



        my %tmpcols = ();
        my %groupbys = ();
        foreach my $tnc (keys %tncs) {
            my $alias = $aliases->{$tnc};
            $tmpcols{"$alias $alias"} = 1;
            $groupbys{"$alias"} = 1;
        }
        %groupbys = prepend_table_name("$TMPTBL$tmptn", %groupbys);

        %selects = prepend_table_name("$TMPTBL$tmptn", %tmpcols);
        foreach my $tbl (@outertbls) {
            my $alias = $aliases->{"$tbl.rowid"};
            $tmpcols{"$alias $alias"} = 1;
            $selects{"min($tbl.rowid) $alias"} = 1;
        }

        @tables = ("$TMPTBL$tmptn");
        my %wheres = ();
        my %tblslookedup = ();
        my %tblsjoined = ();
        foreach my $t1 (@outertbls) {
            foreach my $t2 (keys %{$joins{$t1}}) {
               if ($tblsintmp{$t2}) { 
                   my $joincols = $joins{$t1}->{$t2};
                   foreach my $join (keys %$joincols) {
                       my ($c1, $c2, $junk, $tag)
                           = $join =~ /(\w+) (\w+)( (\w+))?/;
                       my $alias = $aliases->{"$t2.$c2"};
                       if (! $tag) {
                           $tblsjoined{$t1} = 1;
                           $wheres{"$t1.$c1 = $TMPTBL$tmptn.$alias"} = 1;
                       }
                   }
               } 
            }
        }

# Deal with lookups.  Could be prettier, but works.
# To limit the number of queries, the first lookup to a new table is done
# without creating another temporary table. 
        my %wheres2;
        my %selects2;
        my @lookuptbls;
        foreach my $t1 (@outertbls) {
            foreach my $t2 (keys %{$joins{$t1}}) {
               if ($tblsintmp{$t2} || $tblsintmp{$t1}) { 
                   my $joincols = $joins{$t1}->{$t2};
                   foreach my $join (keys %$joincols) {
                       my ($c1, $c2, $junk, $tag)
                           = $join =~ /(\w+) (\w+)( (\w+))?/;
                       my $alias = $aliases->{"$t2.$c2"};
                       if ($tag) {
                           my $fo = get_field_object_from_tag($tag);
                           my ($lutag, $lutbl, $lucol) = $fo->get_names;
                           my $aliaslu = $aliases->{"$lutbl.$lucol $lutag"};
#warn "lookup $lutbl.$lucol $aliaslu where $t1.$c1 = $t2.$c2\n";

                           my $alias1 = $alias;
                           my $lucol2 = $c1;
                           if ($lutbl eq $t2) {
                               next unless $tblsintmp{$t1};
                               $lucol2 = $c2;
                               $alias1 = $aliases->{"$t1.$c1"};
                           } else {
                               next unless $tblsintmp{$t2};
                           }

                           if (! $tblslookedup{$t1}) {
# first lookup joining a new table, no need for another temporary.
                               $tblslookedup{$t1} = "$t2.$c2";
                               $wheres{"$t1.$c1 = $TMPTBL$tmptn.$alias1"} = 1;
                           } else {
# table has been joined in a previous lookup, therefore make a query
# into a separate temporary table, and join that temporary table.
                               my $aliaslu2 = $aliases->{"$lutbl.$lucol2"};
                               $tmptlun++;
                               $query = "select\n$lucol $aliaslu"
                                      . ", $lucol2 $aliaslu2"
                                      . "\nfrom $lutbl into temp "
                                      . "${TMPTBL}lu$tmptlun";
warn "$query;\n" if $::TRACE;
                               push @queries, $query;
                               $selects{"min(${TMPTBL}lu$tmptlun.rowid)"
                                              . " zlu$tmptlun"} = 1;
                               push @lookuptbls, "${TMPTBL}lu$tmptlun";
                               $wheres{"${TMPTBL}lu$tmptlun.$aliaslu2"
                                       . " = $TMPTBL$tmptn.$alias1"} = 1;
                               my $tn = $tmptn + 1;
                               $selects2{$aliaslu} =
                                   "${TMPTBL}lu$tmptlun.$aliaslu $aliaslu";
                               $wheres2{"${TMPTBL}lu$tmptlun.rowid"
                                       . " = $TMPTBL$tn.zlu$tmptlun"} = 1;
                           }
                       }
                   }
               } 
            }
        }


        

        push @tables, @lookuptbls;
        push @tables, @outertbls;
        $query = "select\n" . join (",\n", keys %selects)
               . "\nfrom\n" . join (",\nouter ", @tables)
               . "\nwhere\n" . join ("\nand ", keys %wheres)
               . "\ngroup by\n" . join (",\n", keys %groupbys);
        $tmptn++;
        $query .= "\ninto temp $TMPTBL$tmptn";

warn "$query;\n" if $::TRACE;
        push @queries, $query;

#the query for the rows matching the rowids fetched in the previous
#query, which will put the results into a temporary table


        $more = 0;
        %wheres = %wheres2;
        @tables = ("$TMPTBL$tmptn");
        push @tables, @lookuptbls;
        push @tables, @outertbls;
        %selects = prepend_table_name("$TMPTBL$tmptn", %tmpcols);
        foreach my $t1 (@outertbls) {
            @colsa = $fl->get_columns($t1);
            for (my $i = 0; $i < @colsa; $i++) {
                if (defined $tblslookedup{$t1}
                    && $tblslookedup{$t1} eq "$t1.$colsa[$i]") {
                    splice (@colsa, $i, 1);
                    $i--;
                }
            }

            %cols = ();
            map { $cols{$_} = 1; } @colsa;
            my %newtncs = prepend_table_name($t1, %cols);
            %tncs = (%tncs, %newtncs);
            %newtncs = append_aliases(%newtncs);
            %selects = (%selects, %newtncs);
            my $alias = $aliases->{"$t1.rowid"};
            $wheres{"$TMPTBL$tmptn.$alias = $t1.rowid"} = 1;
            $tblsintmp{$t1} = 1;
        }

#change some of the tables, for lookups
        foreach my $sel (keys %selects) {
            my ($alias) = $sel =~ / (\w+)$/;
            if ($selects2{$alias}) {
                delete $selects{$sel};
                $selects{$selects2{$alias}} = 1;
            }
        }

        my @newoutertbls;
        foreach my $t1 (keys %tblsjoined) {
            foreach my $t2 (keys %{$joins{$t1}}) {
               unless ($tblsintmp{$t2}) {
                   $more = 1;
                   push @newoutertbls, $t2;
               }
            }
        }
        @outertbls = @newoutertbls;



        $query = "select\n" . join (",\n", keys %selects)
               . "\nfrom\n" . join (",\nouter ", @tables)
               . "\nwhere\n" . join ("\nand ", keys %wheres);

        $tmptn++;

    }

    my $tn = $tmptn - 1;
    if ($tn > 0) {
        my $alias = $aliases->{"$current_tbl.rowid"};
        $query .= "\norder by $TMPTBL$tn.$alias";
#    } else {
#        $query .= "\norder by $current_tbl.rowid";
    }
    push  @queries, $query;


#execute the queries

warn "$query\n" if $::TRACE;
warn "values for 1st query:\n" . join ("\n", @vals) . "\n" if $::TRACE;

    my $errmsg;
    for (my $i = 0; $i < $#queries; $i++) {
        $sth = $DB->prepare($queries[$i]);
        if ($sth) {
            my $result;
            if ($i == 0 && @vals) {
                $result = $sth->execute(@vals);
            } else {
                $result = $sth->execute;
            }
            if (!defined $result) {
                $errmsg = $DBI::errstr;
                last;
            }
        }
        else {
            $errmsg = $DBI::errstr; # =~ /SQL:[^:]*:\s*(.*)/;
#            warn "ERROR:\n$DBI::errstr\noccurred after\n$queries[$i]\n";
            last;
        }
    }
    
    if (@vals && $#queries == 0) {
        execute_query( $subform, $queries[$#queries], \@vals );
    } else {
        execute_query( $subform, $queries[$#queries] );
    }

# drop temporary tables
    my @drops;
    while ($tn > 0) {
        push @drops, "drop table $TMPTBL$tn";
        $tn--;
    }
    for (my $i = $tmptlun; $i > 0; $i--) {
        push @drops, "drop table ${TMPTBL}lu$i";
    }

    for (my $i = $#drops; $i >= 0; $i--) {
        $sth = $DB->prepare($drops[$i]);
        if ($sth) {
            $sth->execute;
        }
#        else {
#            warn "ERROR:\n$DBI::errstr\noccurred after\n$drops[$i]\n";
#        }
    } 

    $GlobalUi->display_error($errmsg) if $errmsg;
}

=pod
sub do_query_take5 {
#sub do_query {
    my ( $field, $widget, $subform ) = @_;
    my $app           = $GlobalUi->{app_object};
    my $current_table = $GlobalUi->get_current_table_name;
    my $TMPTBL1       = "pf_tmp1";
    my $TMPTBL2       = "pf_tmp2";

    generate_query_aliases();
    my $aliases = $app->{'aliases'};
    my ( %qcols,  %tjoins,  %tags );
    my ( %cjoins, %cjoins2, %cjoins3 );

    my $fl = $GlobalUi->get_field_list;
    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {

#$fo->print;
        next if ( defined $fo->{displayonly} );
        my ( $tag, $tbl, $col ) = $fo->get_names;
        my $tnc   = "$tbl.$col";
        my $alias = $aliases->{$tnc};
        my $val   = $GlobalUi->get_screen_value($tag);
        my $v2    = defined $val ? $val : '';
        $qcols{$tbl}->{$col} = $v2;

        #lookups
        if ( defined $fo->{active_tabcol} ) {
            my $t2 = $fo->{join_table};
            my $c2 = $fo->{join_column};
            my ( $t1, $c1 ) = $fo->{active_tabcol} =~ /(\w+)\.(\w+)/;
            my $a1 = $aliases->{"$t1.$c1"};
            my $a2 = $aliases->{"$t2.$c2"};

            if ($a1 ne $a2) {
            $qcols{$t1}->{$c1} = '' unless defined $qcols{$t1}->{$c1};
            $qcols{$t2}->{$c2} = '' unless defined $qcols{$t2}->{$c2};
if ($::TRACE) {
warn "lookup $tbl.$col, where $t1.$c1 = $t2.$c2\n";
warn "Alias 0 = $alias\n";
warn "Alias 1 = $a1\n";
warn "Alias 2 = $a2\n";
}
            $tjoins{$t1}->{$t2}                       = 1;
            $tjoins{$t2}->{$t1}                       = 1;

            $cjoins2{$t1}->{"$TMPTBL1.$a1 = $t2.$c2"} = 1
                 if ($t1 eq $current_table);
            $cjoins2{$t2}->{"$TMPTBL1.$a2 = $t1.$c1"} = 1
                 if ($t2 eq $current_table);

            $cjoins3{$t1}->{"$TMPTBL2.$a2 = $t1.$c1"} = 1;
            $cjoins3{$t2}->{"$TMPTBL2.$a1 = $t2.$c2"} = 1;
            }
        }

        #joins
        if ( defined $tags{$tag} ) {
            my ( $t1, $c1 ) = $tags{$tag} =~ /(\w+)\.(\w+)/;
            my $alias2 = $aliases->{ $tags{$tag} };
warn "join $tnc = $t1.$c1\n" if $::TRACE;
            if ($tnc ne $tags{$tag}) {
                $tjoins{$t1}->{$tbl}                              = 1;
                $tjoins{$tbl}->{$t1}                              = 1;

                $cjoins2{$tbl}->{"$TMPTBL1.$alias = $tags{$tag}"} = 1;
                $cjoins3{$t1}->{"$TMPTBL2.$alias = $tags{$tag}"}  = 1;

                $cjoins2{$t1}->{"$TMPTBL1.$alias2 = $tnc"}        = 1;
                $cjoins3{$tbl}->{"$TMPTBL2.$alias2 = $tnc"}       = 1;
            }
        }
        else {
            $tags{$tag} = "$tbl.$col";
        }
    }

    # set up data for building of queries
    my ( %selects,  %selects2,  %selects3 );
    my ( %groupbys2, %groupbys3 );

    my $groupbyflag = 0;

    my $outerjoins = $tjoins{$current_table};
    foreach my $t ( keys %$outerjoins ) {
        my $ocs = $qcols{$t};
        foreach my $oc ( keys %$ocs ) {
            my $alias = $aliases->{"$t.$oc"};
            $selects2{"min($t.$oc) $alias"}     = 1;
            $groupbyflag                        = 1;
            $selects3{"$TMPTBL2.$alias $alias"} = 1;
            $groupbys3{"$TMPTBL2.$alias"}       = 1;
        }
    }
    foreach my $c ( keys %{ $qcols{$current_table} } ) {
        my $alias = $aliases->{"$current_table.$c"};
        $selects{"$current_table.$c $alias"} = 1;
        $selects2{"$TMPTBL1.$alias $alias"}  = 1;
        $selects3{"$TMPTBL2.$alias $alias"}  = 1;
        my $val = $qcols{$current_table}->{$c};
        if ( length $val > 0 ) {
            my ( $wexpr, $wv ) = query_condition( $current_table, $c, $val );
            $cjoins{$current_table}->{$wexpr} = \@$wv;
        }

        $groupbys2{"$TMPTBL1.$alias"} = 1;
        $groupbys3{"$TMPTBL2.$alias"} = 1;
    }
    foreach my $c ( keys %{ $cjoins2{$current_table} } ) {
        my ($alias) = $c =~ /^\w+\.(\w+)/;
        unless (defined $selects2{"$TMPTBL1.$alias $alias"}) {
            delete $cjoins2{$current_table}->{$c};
        }
    }

    {
        my $tnc   = "$current_table.rowid";
        my $alias = $aliases->{$tnc};
        if ( defined $alias ) {
            $selects{"$tnc $alias"}             = 1;
            $selects2{"$TMPTBL1.$alias $alias"} = 1;
            $selects3{"$TMPTBL2.$alias $alias"} = 1;
            $groupbys2{"$TMPTBL1.$alias"}       = 1;
            $groupbys3{"$TMPTBL2.$alias"}       = 1;
        }
    }

    # build 1st query to get Informix specific "rowid"

    #    my $wheres = join ",\n", keys %{$cjoins{$current_table}};
    my $wheres = '';
    my @wvals  = ();
    foreach my $c ( keys %{ $cjoins{$current_table} } ) {
        $wheres .= "\nand $c";
        my $v = $cjoins{$current_table}->{$c};
        push @wvals, @$v if ref $v;
    }
    $wheres =~ s/\A\nand //;

    my $query =
      "select\n" . join( ",\n", keys %selects ) . "\nfrom\n$current_table";
    $query .= "\nwhere\n$wheres" if $wheres;

    my %wheres3;
    my $froms;
    my ($query2, $query3);
    my $query3flag = 0;
    if ($groupbyflag) {
        $query .= "\ninto temp $TMPTBL1";


        # build 2nd query
        my $joins = join ",\nouter ", keys %$outerjoins;
        $froms = $TMPTBL1;
        $froms .= ",\nouter $joins" if ($joins);
        $wheres = join "\nand ", keys %{ $cjoins2{$current_table} };
        $query2 = "select\n" . join( ",\n", keys %selects2 )
                   . "\nfrom\n$froms";
        $query2 .= "\nwhere\n$wheres" if $wheres;
        $query2 .= "\ngroup by\n" . join( ",\n", keys %groupbys2 );


        # build 3rd query
        $froms = "";
        foreach my $t1 ( keys %tjoins ) {
            if ( $t1 ne $current_table && !defined $outerjoins->{$t1} ) {
                $query3flag = 1;
                $froms .= ",\nouter $t1";
                foreach my $c ( keys %{ $qcols{$t1} } ) {
                    my $alias = $aliases->{"$t1.$c"};
                    $selects3{"min($t1.$c) $alias"} = 1;
                }
                foreach my $c ( keys %{ $cjoins3{$t1} } ) {
                    $wheres3{$c} = 1;
                }
            }
        }
    }


    #do the queries
    warn "$query;\n" . join( " ", @wvals ) . "\n" if $::TRACE;
    my $sth;

    if ($query3flag || $groupbyflag) {
        $sth = $DB->prepare($query);
        if ($sth) {
            $sth->execute(@wvals);
        }
        else {
            warn "1: $DBI::errstr\n";
        }
    }

    my $ralias = $aliases->{"$current_table.rowid"};
    if ($query3flag) {
        $query2 .= "\ninto temp $TMPTBL2";
        $query3 =
            "select\n"
          . join( ",\n", keys %selects3 )
          . "\nfrom\n$TMPTBL2$froms"
          . "\nwhere\n"
          . join( "\nand ", keys %wheres3 )
          . "\ngroup by\n"
          . join( ",\n", keys %groupbys3 )
          . "\norder by $ralias";

        warn "$query2;\n" if $::TRACE;
        warn "$query3;\n" if $::TRACE;
        my $sth = $DB->prepare($query2);
        if ($sth) {
            $sth->execute;
        }
        else {
            warn "2: $DBI::errstr\n";
        }

        execute_query( $subform, $query3 );

        $sth = $DB->prepare("drop table $TMPTBL2");
        if ($sth) {
            $sth->execute;
        }
        else {
            warn "3: $DBI::errstr\n";
        }
    }
    elsif ($groupbyflag) {
        $query2 .= "\norder by $ralias";
        warn "$query2;\n" if $::TRACE;
        execute_query( $subform, $query2 );
    }
    else {
        $query .= "\norder by $ralias";
        execute_query( $subform, $query, \@wvals );
    }

    if ($query3flag || $groupbyflag) {
        $sth = $DB->prepare("drop table $TMPTBL1");
        if ($sth) {
            $sth->execute;
        }
        else {
            warn "4: $DBI::errstr\n";
        }
    }
}
=cut

sub query_condition {
    my ( $tbl, $col, $val ) = @_;
    my $err = $GlobalUi->{error_messages};

    #warn "parms = :$tbl:$col:$val:\n";
    # Determine what kind of comparison should be done

    my $op    = '=';
    my $cval  = $val;
    my @cvals = ();

    if ( $val eq '=' ) { $op = 'is null'; $cval = undef; }
    elsif ( $val =~ /^\s*(<<|>>)(.*?)$/ ) {
        $cval = query_condition_minmax($tbl, $col, $val);
    }
    elsif ( $val =~ /^\s*(([<>][<=>]?)|!?=)(.*?)$/ ) {
        $op   = $1;
        $cval = $3;
    }
    elsif ( $val =~ /^(.+?):(.+)$/ ) {
        $op = "between ? and ";
        push( @cvals, $1 );
        $cval = $2;
    }
    elsif ( $val =~ /^(.+?)\|(.+)$/ ) {    # might should use in ($1,$2)
        $op = "= ? or $col = ";
        push( @cvals, $1 );
        $cval = $2;
    }
    # SQL wildcard characters
    elsif ( $val =~ /[*%?]/ ) { $cval =~ tr/*?/%_/; $op = 'like'; }

    my $where = "$tbl.$col $op" . ( defined($cval) ? ' ?' : '' );
    push( @cvals, $cval ) if defined($cval);
    return ( $where, \@cvals );
}

#To handle min/max, do a query, then add
# the results to the where clause.  Ex, if asking for '>>' from
# table and column 't.c', then the query here is:
# select max(t.c) from t
# If the result of that query is '41', then we add this to the wheres:
# t.c = 41
sub query_condition_minmax {
    my $tbl = shift;
    my $col = shift;
    my $qc  = shift;

    my $mm = 'max';
    $mm = 'min' if $qc =~ /<</;

    my $query = "select $mm($tbl.$col) from $tbl";

    my $sth = $DB->prepare($query);
    if ($sth) {
        $sth->execute;
    }
    else {
        warn "$DBI::errstr\n";
    }
    my $ref = $sth->fetchrow_array;
warn "query condition min/max is $ref\n" if $::TRACE;
    return $ref;
}

sub execute_query {
    my $subform       = shift;
    my $query         = shift;
    my $vals          = shift;
    my $app           = $GlobalUi->{app_object};
    my $current_table = $GlobalUi->get_current_table_name;
    my $err           = $GlobalUi->{error_messages};

    $GlobalUi->display_status( $err->{'se10.'} );

#warn Data::Dumper->Dump([$vals], ['vals']);
    # update row list
    @$vals = () unless ref $vals;
    my $row = $RowList->stuff_list( $query, \@$vals, $DB, $app );
    my $size = $RowList->list_size;

    # Print outcome of query to status bar
    if    ( $size == 0 ) { $GlobalUi->display_status('no11d'); }
    elsif ( $size == 1 ) { $GlobalUi->display_status('1 8d'); }
    else {
        my $msg = "$size " . $err->{'ro7d'};
        $GlobalUi->display_status($msg);
    }

    #execute any instructions triggered after a query
    trigger_ctrl_blk( 'after', 'query', $current_table );

    # display the first table
    display_row( $subform, $row );

    # change focus to the user interface
    $GlobalUi->change_mode_display( $subform, 'perform' );

    warn "TRACE: leaving do_query\n" if $::TRACE;
}

=pod
sub do_query_take2 {
#sub do_query {
    my ( $field, $widget, $subform ) = @_;

    warn "TRACE: entering do_query\n" if $::TRACE;

    my $err = $GlobalUi->{error_messages};
    my $app = $GlobalUi->{app_object};

    #my $masters = $app->getField('MASTERS');
    my $masters = undef;    # not hookup up yet
    my @tables =
      @{ $GlobalUi->{attribute_table_names} };    # attribute section names
    my $fl = $GlobalUi->get_field_list;

    my ( $table, $detail, $msg );
    my %tags;

    #clear_textfields;

    #$fl->print_list;
    #exit;

    # Handle queries for Master/Detail
    if ($masters)                                 # TBD
    {
        my $mdpair    = $$masters[0];
        my $indexes   = $app->getField('form_name_indexes');
        my $formindex = $$indexes{ $app->getField('form_name') };
        my $mdmode    = $app->getField('md_mode');
        my $mdindex   = $mdmode eq 'm' ? 0 : $mdmode eq 'd' ? 1 : undef;
        die "Masters exist in instructions but md_mode is '$mdmode'"
          unless defined($mdindex);
        $table  = $$mdpair[$mdindex];
        $detail = $mdindex != 0;
    }

    # Process field objects from "field_list"
    my $current_table = $GlobalUi->get_current_table_name;
    my %wheres        = ();
    my @vals          = ();
    my %tbls          = ();

    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my ( $tag, $tbl, $col ) = $fo->get_names;

        #$fo->print;
        next unless $tbl;
        next if ( defined $fo->{displayonly} );
        next if $masters && $tbl ne $table;    # just a guess ...

        #lookups
        if ( defined $fo->{active_tabcol} ) {
            my $t2 = $fo->{join_table};
            my $c2 = $fo->{join_column};
            $wheres{"$fo->{active_tabcol} = $t2.$c2"} = ();
            $tbls{$t2} = 1;
            next;
        }

        #composite joins
        #  see note in DigestPer.pm

        $tbls{$tbl} = 1;
        if ( !$masters ) {    # handle joins
            my $t2 = $fo->{join_table};
            my $c2 = $fo->{join_column};
            if ( defined($t2) && defined($c2) ) {

                #warn "in join:";
                #$fo->print;
                #exit;
                $wheres{"$tbl.$col = $t2.$c2"} = ();
                $tbls{$t2} = 1;
            }
        }

        #do joins.  Since there can be more than one field object with
        #  the same tag, this code detects duplicates with a hash.
        #  When a duplicate is found, the related column.table is joined.
        if ( defined $tags{$tag} ) {
            $wheres{"$tags{$tag} = $tbl.$col"} = ();
        }
        else {
            $tags{$tag} = "$tbl.$col";
        }
        #        my $val = $fo->get_value;
        # val=fo->get_value is incorrect.  We want what the user entered, not
        # the default values.
        #my $form2 = $app->getForm('Run0');
        #my $subform2 = $form2->getSubform('DBForm');
        #        my $val = $subform2->getWidget($tag)->getField('VALUE');
        #warn "calling get_screen_val";
        my $val = $GlobalUi->get_screen_value($tag);
        warn "tag = :$tag: tbl = :$tbl: col = :$col:\n" if $::TRACE_DATA;

        #next unless (defined($val) && $val ne '');
        next if ! defined $val || $val eq '';

        # Is this right?  Always want to compare to the current table?
        # Scenario: have 3 tables x, y, and z, and the current table is x.
        # We could want to filter on some condition "where y.c = z.c",
        # in which case the line below should not be present.
        next unless $tbl eq $current_table;

        # Determine what kind of comparison should be done

        my $op    = '=';
        my $cval  = $val;
        my @cvals = ();

        # SQL wildcard characters
        if ( $val =~ /[*%?]$/ ) { $cval =~ tr/*?/%_/; $op = 'like'; }

        if ( $val eq '=' ) { $op = 'is null'; $cval = undef; }
        elsif ( $val =~ /^(<<|>>)(.*?)$/ ) {

          #FIX looks like this can be done by doing a query here, then adding
          # the results to the where clause.  Ex, if asking for '>>' from
          # table and column 't.c', then the query here is:
          # select max(t.c) from t
          # If the result of that query is '41', then we add this to the wheres:
          # t.c = 41
            $msg = $err->{'th26d'};
            $msg = $msg . ": $1";
            $GlobalUi->display_status($msg);
        }
        elsif ( $val =~ /^([<>][<=>]?)(.*?)$/ ) {
            $op   = $1;
            $cval = $2;
        }
        elsif ( $val =~ /^(.+?):(.+)$/ ) {
            $op = "between ? and ";
            push( @cvals, $1 );
            $cval = $2;
        }
        elsif ( $val =~ /^(.+?)\|(.+)$/ ) {    # might should use in ($1,$2)
            $op = "= ? or $col = ";
            push( @cvals, $1 );
            $cval = $2;
        }
        my $where = "$tbl.$col $op" . ( defined($cval) ? ' ?' : '' );
        push( @cvals, $cval ) if defined($cval);
        $wheres{$where} = \@cvals if length $where > 0;
    }

    my $wheres = join " and\n", keys %wheres;
    foreach my $wherev ( values %wheres ) {
        push @vals, @$wherev if defined $wherev;
    }

    #don't want outer join with table that doesn't share a condition
    #with the current table.
    my $query2flag = 0;
    my %outers;
    foreach $table ( keys %tbls ) {
        next if $table eq $current_table;
        foreach my $w ( keys %wheres ) {
            $outers{$table} = 1 if $w =~ /$table/ && $w =~ /$current_table/;
            if ($w =~ /$table/ && $w =~ /$current_table/) {
#                $outers{$table} = 1; 
#            } else {
## If we reach this spot, then the query as constructed will be too slow to
## be practical.  
#                $query2flag = 1;
#            }
        }
    }

    generate_query_aliases();
    my $aliases = $app->{'aliases'};

    my $tables = $current_table;
    my ( @acols, $columns, $query );
    my @groupbys;
    my $groupby_flag = 0;
    foreach $table ( keys %tbls ) {

        #warn "table = :$table:\n" if $::TRACE;
        my $groupby_this_table_flag = 0;
        if ( $table ne $current_table ) {

            #FIX -- Using "outer" in the list of tables is Informix specific
            $tables .= $outers{$table} ? ", outer $table" : ", $table";
            $groupby_this_table_flag = 1;
            $groupby_flag            = 1;
        }
        my @cols = $fl->get_columns($table);
        if ( @cols > 0 ) {
            my %hcols = ();
            for ( my $i = $#cols ; $i >= 0 ; $i-- ) {
                $hcols{ $cols[$i] } = 1;
            }
            if ($groupby_this_table_flag) {
                foreach my $col ( keys %hcols ) {
                    $col = "$table.$col";
                    next unless defined $aliases->{$col};
                    $col = "min($col) $aliases->{$col}";
                    push @acols, $col;
                }
            }
            else {
                foreach my $col ( keys %hcols ) {
                    $col = "$table.$col";
                    next unless defined $aliases->{$col};
                    push @groupbys, $col;
                    $col .= " $aliases->{$col}";
                    push @acols, $col;
                }
            }
        }
    }
    $columns = join( ",\n", @acols );
    $query =
      "select\n$columns\nfrom\n$tables" . ( $wheres ? "\nwhere\n$wheres" : '' );
    $query .= "\ngroup by\n" . join( ",\n", @groupbys ) if $groupby_flag;

    warn "wheres: $wheres\ntables: $tables\nquery:\n$query\n" if $::TRACE;
    warn "vals: " . join( ' : ', @vals ) . "\n" if $::TRACE;

    $GlobalUi->display_status( $err->{'se10.'} );

    # update row list
    my $row = $RowList->stuff_list( $query, \@vals, $DB, $app );
    my $size = $RowList->list_size;

    # Print outcome of query to status bar
    if    ( $size == 0 ) { $GlobalUi->display_status( $err->{'no11d'} ); }
    elsif ( $size == 1 ) { $GlobalUi->display_status( $err->{'1 8d'} ); }
    else {
        $msg = "$size " . $err->{'ro7d'};
        $GlobalUi->display_status($msg);
    }

    #execute any instructions triggered after a query
    trigger_ctrl_blk( 'after', 'query', $current_table );

    # display the first table
    display_row( $subform, $row );

    # change focus to the user interface
    $GlobalUi->change_mode_display( $subform, 'perform' );

    warn "TRACE: leaving do_query\n" if $::TRACE;
}

=cut

sub next_alias {
    my $i = shift;
    my $reserved_words =
        'ada|add|all|and|any|are|asc|avg|bit|bor|day|dec'
      . '|end|eqv|for|get|iif|imp|int|key|lag|map|max|min'
      . '|mod|mtd|new|non|not|off|old|out|pad|qtd|ref|row'
      . '|set|sql|sum|top|use|var|wtd|xor|yes|ytd';
    my $alias;
        do {
            $alias =
                chr( $i / ( 26 * 26 ) + ord('a') )
              . chr( ( $i / 26 ) % 26 + ord('a') )
              . chr( $i % 26 + ord('a') );
            $i++;
        } while ( $alias =~ /$reserved_words/ );
    return ($alias, $i);
}

sub generate_query_aliases {
    my $app = $GlobalUi->{app_object};

    my $fl = $GlobalUi->get_field_list;
    $fl->reset;
    my $i = 0;
    my $j = 0; #(25 * 10) + 9;
    my $alias;
    my %aliases;

    while ( my $fo = $fl->iterate_list ) {
        next if $fo->{displayonly};
        ($alias, $i) = next_alias($i);
        my ( $tag, $tbl, $col ) = $fo->get_names;
        $aliases{"$tbl.$col $tag"} = $alias;
        $aliases{"$tbl.$col"} = $alias;
        if (defined $fo->{join_table}) {
            $tbl = $fo->{join_table};
            $col = $fo->{join_column};
            unless (defined $aliases{"$tbl.$col $tag"}) {
                ($alias, $i) = next_alias($i);
                $aliases{"$tbl.$col $tag"} = $alias;
                $aliases{"$tbl.$col"} = $alias;
            }
        }
        unless (defined $aliases{"$tbl.rowid"}) {
            $alias = 'z'
              . chr( $j / 10 + ord('0') )
              . chr( $j % 10 + ord('0') );
            $j++;
            $aliases{"$tbl.rowid"} = $alias;
        }
    }
#warn Data::Dumper->Dump([%aliases], ['aliases']);
    $app->{'aliases'} = \%aliases;
}

sub do_add {
    my ( $field, $widget, $subform ) = @_;

    warn "TRACE: entering do_add\n" if $::TRACE;

    my $app           = $GlobalUi->{app_object};
    my $current_table = $GlobalUi->get_current_table_name;
    my $driver        = $DB->{'Driver'}->{'Name'};
    my $fl            = $GlobalUi->get_field_list;
    my $fo            = $fl->get_field_object( $current_table, $field );

    my $singleton = undef;

    my ( @ca, @values, $row, $msg );
    $GlobalUi->change_mode_display( $subform, 'add' );
    $GlobalUi->update_subform($subform);

    # First test the input of the current field

    my $v = $fo->get_value;
    my $rc = $fo->validate_input( $v, 'add' );
    return if $rc != 0;

    generate_query_aliases();

    return if !verify_composite_joins();

    # test the subform as a whole
    $fl->reset;
    while ( $fo = $fl->iterate_list ) {
        my ( $tag, $tbl, $col ) = $fo->get_names;
        next if $tbl ne $current_table;    # FIX: single table adds...?

        my $v = $fo->get_value;
        next if $fo->is_serial || defined( $fo->{displayonly} );

 	# special handling for subscript attribute
        if (   defined $fo->{subscript_floor}
            && defined $fo->{subscript_ceiling} )
        {
            $singleton = $fo if !defined $singleton;
	    $rc = $singleton->format_value_for_database( 'add', $fo);
	    return $rc if $rc != 0;
	    next if ! $fl->is_last;
        }
	else {
	    $rc = $fo->format_value_for_database( 'add', undef );
	}
	return $rc if $rc != 0;

        # add col and val for the sql add

          if ( $fl->is_last ) {    # add singleton on last iteration
            if ( defined $singleton ) {
                my ( $stag, $stbl, $scol ) = $singleton->get_names;
                my $sval = $singleton->get_value;
                push( @ca,     $scol );
                push( @values, $sval );
            }
        }
        push( @ca,     $col );
        push( @values, $v );
    }

    # insert to db

    my ( $serial_val, $serial_fo, $serial_col );
    undef $rc;

    my $holders = join ', ', map { "?" } @ca;
    my $cols = join ', ', @ca;

    my $cmd = "insert into $current_table ($cols) values ($holders)";
    my $sth = $DB->prepare($cmd);

    if ($sth) {
        $rc = $sth->execute(@values);
    }
    else {
        my $m = $GlobalUi->{error_messages}->{'ad21e'};
        $GlobalUi->display_error($m);
    }
    if ( $driver eq "Informix" ) {
        $serial_fo  = $fl->get_serial_field;       # returns one field or undef
        $serial_col = $serial_fo->{column_name};
        $serial_val = $sth->{ix_sqlerrd}[1];       # get db supplied value

        if ( defined($serial_val) && defined($serial_col) ) {

            $serial_fo->set_value($serial_val);
            $GlobalUi->set_screen_value( $serial_col, $serial_val );
        }
    }
    else { warn "$driver serial values not currently supported"; }

    if ( !defined $rc ) {
        my $m = ": $DBI::errstr";
        $GlobalUi->display_comment('db16e');
        $GlobalUi->display_error($m);
        $GlobalUi->change_mode_display( $subform, 'add' );
        return;
    }

    # refreshes the values on the screen after add
    my $refetcher = $INSERT_RECALL{$driver} || \&Default_refetch;
    if ( defined($refetcher) ) {
        $row =
          &$refetcher( $sth, $current_table, \@ca, \@values, $serial_col,
            $serial_val );
    }
    if ( defined($row) ) {
        $RowList->add_row($row);
        display_row( $subform, $RowList->current_row );
        $msg = $GlobalUi->{error_messages}->{'ro6d'};
        $GlobalUi->display_status($msg);
        trigger_ctrl_blk( 'after', 'add', $current_table );
    }
    else {
        $msg = $GlobalUi->{error_messages}->{'fa39e'};
        $GlobalUi->display_error($msg);
    }
    $subform->setField( 'EXIT', 1 );    # back to menu
    $GlobalUi->change_mode_display( $subform, 'perform' );

    warn "TRACE: leaving do_add\n" if $::TRACE;
    return undef;
}

sub do_update {
    my $field   = shift;
    my $widget  = shift;
    my $subform = shift;

    return if !verify_composite_joins();

    my $app       = $GlobalUi->{app_object};
    my $form      = $GlobalUi->{form_object};
    my $fl        = $GlobalUi->get_field_list;
    my $table     = $GlobalUi->get_current_table_name;
    my $singleton = undef;

    my %wheres = ();
    my %upds   = ();

    #    my $row	= {};
    my %reassemblies;

    my $aliases      = $app->{'aliases'};
    my %aliased_upds = ();
    my $cur_row      = $RowList->current_row;

    $GlobalUi->change_mode_display( $form, 'update' );
    $GlobalUi->update_subform($subform);

    $fl->reset;
    while ( my $fo = $fl->iterate_list ) {
        my ( $tag, $tbl, $col ) = $fo->get_names;
        next if $tbl ne $table;    # guess...

        # reexamine the placement of this test
        next if !( $fo->allows_focus('update') );

        my $tnc   = "$tbl.$col";
        my $alias = $aliases->{$tnc};
        next unless $cur_row->{$alias};

        # get value from field
        my $v  = $fo->get_value;
        my $rc = 0;

        $GlobalUi->change_mode_display( $subform, 'update' );

#        my $rc = $fo->validate_input( $v, 'update' );
#        return if $rc != 0;

        # special handling for subscript attribute
        if (   defined $fo->{subscript_floor}
            && defined $fo->{subscript_ceiling} )
        {
            $singleton = $fo if !defined $singleton;
            $rc = $singleton->format_value_for_database( 'update', $fo );
            return $rc if $rc != 0;
            next       if !$fl->is_last;
        }
        else {
            $rc = $fo->format_value_for_database( 'update', undef );
        }
        return $rc if $rc != 0;

        # add col and val for the sql add

        my $fv = $cur_row->{$alias} if defined $alias;

        if ( $fl->is_last ) {    # add singleton on last iteration
            if ( defined $singleton ) {
                my ( $stag, $stbl, $scol ) = $singleton->get_names;
                my $sval = $singleton->get_value;

                if ( $sval ne $fv ) {
                    $upds{$scol}          = $sval;
                    $aliased_upds{$alias} = $sval;
                }
            }
        }

        if ( $v ne $fv ) {
            $upds{$col}           = $v;
            $aliased_upds{$alias} = $v;
        }

    }
#    $fl->print_list;

    my @updcols = keys(%upds);
    if ( @updcols == 0 ) {
        $GlobalUi->display_status('no14d');
        $GlobalUi->change_mode_display( $form, 'update' );
        return;
    }
    my @updvals = map { $upds{$_} } @updcols;
    warn "updcols: [@updcols]" if $::TRACE_DATA;
    my $sets = join( ', ', map { "$_ = ?" } @updcols );

    my $ralias = $aliases->{"$table.rowid"};
    my @wherevals = ( $cur_row->{$ralias} );
    my $cmd       = "update $table set $sets where rowid = ?";
    warn "cmd: [$cmd]"       if $::TRACE_DATA;
    warn "ud: [@updvals]"    if $::TRACE_DATA;
    warn "whv: [@wherevals]" if $::TRACE_DATA;

    my $rc = $DB->do( $cmd, {}, @updvals, @wherevals );
    if ( !defined $rc ) {

        # display DB error string
        my $m1 = $GlobalUi->{error_messages}->{'db16e'};
        my $m2 = ": $DBI::errstr";
        $GlobalUi->display_comment($m1);
        $GlobalUi->display_error($m2);
        $GlobalUi->change_mode_display( $form, 'update' );
        return;
    }
    else {
        my $m = $GlobalUi->{error_messages}->{'ro10d'};
        $m = ( 0 + $rc ) . " " . $m;
        $GlobalUi->display_status($m);

        # Since the new value is now in, change the where value...
        my $tmp = $RowList->current_row;

        #	grep {$tmp->{$_} = $row->{$_} = $updvals[$updinds{$_}];}
        #	        @updcols;
        #this assumes only 1 row changed.  If this row was 1 of 2+ identical
        #rows, then this is wrong.

        map { $tmp->{$_} = $aliased_upds{$_}; } keys %aliased_upds;
        trigger_ctrl_blk( 'after', 'update', $table );
        display_row( $subform, $RowList->current_row );
    }
    $subform->setField( 'EXIT', 1 );    # back to menu
    $GlobalUi->change_mode_display( $subform, 'perform' );
}

sub display_row {
    my $form = shift;
    my $row  = shift;

    warn "TRACE: entering display_row\n" if $::TRACE;

    #warn Data::Dumper->Dump([$row], ['row']);
    return if !$row;
    my $app     = $GlobalUi->{app_object};
    return if $app->{deletedrow};

    my $subform    = $form->getSubform('DBForm') || $form;
    my %table_hash = ();
    my %field_hash = ();
    my @ofs;
    my $aliases = $app->{'aliases'};
    my $sl      = $GlobalUi->get_field_list;

    $sl->reset;
    while ( my $fo = $sl->iterate_list ) {
        my ( $tag, $table, $col ) = $fo->get_names;
        my $tnc = "$table.$col";

        @ofs = ();
        if ( defined $table ) {
            push @ofs, $tnc;
            if ( !defined( $table_hash{$table} ) ) {
                $table_hash{$table} = 1;
                push @ofs, $table;
            }
        }
        push @ofs, $col;
        trigger_ctrl_blk( 'before', 'display', @ofs );

        my $alias = $aliases->{$tnc};
        my $alias2 = $aliases->{"$tnc $tag"};
        my $val;
        $val = $row->{$alias2} if defined $alias2;
        $val = $row->{$alias} if defined $alias && !defined $val;
        if ( !defined $field_hash{$tag} || defined $val ) {
            $field_hash{$tag} = 1;
            warn "tag = $tag: val = $val:\n" if $::TRACE_DATA;

            my $pos = 0;
            my $rc  = 0;
            $fo->set_value($val);
            ( $val, $pos, $rc ) = $fo->format_value_for_display( $val, $pos );
            $GlobalUi->set_screen_value( $tag, $val );

            @ofs = ();
            push @ofs, $tnc if defined $table;
            push @ofs, $col;
            trigger_ctrl_blk( 'after', 'display', @ofs );
        }
    }

    $app->{fresh} = 1;
    @ofs = keys %table_hash;
    trigger_ctrl_blk( 'after', 'display', @ofs );

    warn "TRACE: leaving display_row\n" if $::TRACE;
}

#  Post-Add/Update refetch functions:
sub Pg_refetch {
    my $sth   = shift;
    my $table = shift;

    my $oid = $sth->{'pg_oid_status'};
    my $row = $DB->selectrow_hashref("select * from $table where oid='$oid'");
    return $row;
}

sub Informix_refetch {
    my $sth    = shift;    # statement handle; ignored.
    my $table  = shift;    # table to query
    my $cols   = shift;    # columns to query
    my $vals   = shift;    # values to query
    my $fld    = shift;    # serial field name
    my $serial = shift;    # serial field value

    warn "entering Informix_refetch\ntable = $table\n" if $::TRACE;

    my $aliases = $GlobalUi->{app_object}->{aliases};
    my $rowid   = $sth->{ix_sqlerrd}[5];
    my $selects = '';
    foreach my $tnc ( keys %$aliases ) {
        next if $tnc =~ / (\w+)$/;
        my ($t) = $tnc =~ /^(\w+)/;
        my $alias = $aliases->{$tnc};
        $selects .= ",\n$tnc $alias" if ( $t eq $table );
    }
    $selects =~ s/^,\n//;

    my ( $lsth, $query, $row );
    $query = "SELECT\n$selects\nFROM $table WHERE rowid = $rowid";
    warn "refetch query =\n$query\n" if $::TRACE;
    $lsth = $DB->prepare($query);
    if ($lsth) {
        $row = $DB->selectrow_hashref( $query, {} );
    }

    return $row if defined($row);
    return undef;
}

# not tested
sub Oracle_refetch {
    my $sth   = shift;    # statement handle; ignored.
    my $table = shift;    # table to query
    my $cols  = shift;    # columns to query
    my $vals  = shift;    # values to query

    my $wheres = join ' AND ', map { "$_ = ?" } @$cols;
    my $query = "SELECT * FROM $table WHERE $wheres";

    # prepare is skipped in selectrow_hashref for Oracle?
    $sth = $DB->prepare($query);
    my $row = $DB->selectrow_hashref( $query, {}, @$vals );

    return $row;
}

# When we don't know how to get the row-ID or similar marker, just query
# on all the values we know...
sub Default_refetch {
    my $sth   = shift;    # statement handle; ignored.
    my $table = shift;
    my $cols  = shift;    # columns to query
    my $vals  = shift;    # values to query

    my $wheres = join ' AND ', map { "$_ = ?" } @$cols;
    my $query  = "SELECT * FROM $table WHERE $wheres";
    my $row    = $DB->selectrow_hashref( $query, {}, @$vals );
    return $row;
}

# What a kludge...  required by Curses::Application
package main;

1;
__DATA__
%forms = ( DummyDef => {} );


__END__


# need to update the pod once the features are in place


=head1 NAME

DBIx::Perform - Informix Perform(tm) emulator

=head1 SYNOPSIS

On the shell command line: 

=over

export DB_CLASS=[Pg|mysql|whatever] DB_USER=usename DB_PASSWORD=pwd

[$install-bin-path/]generate dbname tablename  > per-file-name.per

[$install-bin-path/]perform per-file-name.per  (or pps-file-name.pps)

=back

Or in perl, with the above environment settings:

=over

  DBIx::Perform::run ($filename_or_description_string);

=back

=head1 ABSTRACT

Emulates the Informix Perform character-terminal-based database query
and update utility.  

=head1 DESCRIPTION

The filename given to the I<perform> command may be a Perform
specification (.per) file.  The call to the I<run> function may be a
filename of a .per file or of a file pre-digested by the
DBIx::Perform::DigestPer class (extension .pps).  [Using
pre-digested files does not appreciably speed things up, so this
feature is not highly recommended.]

The argument to the I<run> function may also be a string holding the
contents of a .per or .pps file, or a hash ref with the contents of a
.pps file (keys db, screen, tables, attrs).

The database named in the screen spec may be a DBI connect argument, or
just a database name.  In that case, the database type is taken from
environment variable DB_CLASS.  The username and password are taken from
DB_USER and DB_PASSWORD, respectively.

Supports the following features of Informix's Perform:

 Field Attributes: COLOR, NOENTRY, NOUPDATE, DEFAULT, UPSHIFT, DOWNSHIFT,
		   INCLUDE, COMMENTS, NOCOMPARE.
	NOCOMPARE is an addition of ours for a hack of updating a
	sequence's next value in Postgres.  A field marked NOCOMPARE
	is never included in the WHERE clause in an Update.

 2-table Master/Detail  (though no query in detail mode)

 VERY simple control blocks (nextfield= and let f1 = f2 op f3-or-constant)
 
=head1  COMMANDS

The first letter of each item on the button menu can be pressed.

Q = query.  Enter values to match in fields to match.  Field values
	may start with >, >=, <, <=, contain val1:val2 or val1|val2
	or end with * (for wildcard suffix).  Value of the "=" sign 
	matches a null value.  The ESC key queries; Ctrl-C aborts.

A = add.  Enter values for the row to add.  ESC or Ctrl-C when done.

U = update.  Edit row values.  ESC or Ctrl-C when done.  

R = remove.  NO CONFIRMATION!  BE CAREFUL USING THIS!

E = exit.

M / D = Master / Detail screen when a MASTER OF relationship exists between
	two tables.


=head1  REQUIREMENTS

Curses Curses::Application Curses::Forms Curses::Widgets

DBI  and DBD::whatever

Note: For the B<generate> function / script to work, the DBD driver
must implement the I<column_info> method.

=head1   ENVIRONMENT VARIABLES

DB_CLASS	this goes into the DBI connect string.  NOTE: knows how
		to prefix database names for Pg and mysql but not much else.

DB_USER		User name for DBI->connect.

DB_PASSWORD	Corresponding.

BGCOLOR		One of eight Curses-known colors for form background
    		(default value is 'black').

FIELDBGCOLOR	Default field background color (default is 'blue').
    		Fields' background colors may be individually overridden
		by the "color" attribute of the field.

Note, any field whose background matches the form background gets
displayed with brackets around it:   [field_here] .

=head1	FUNDING CREDIT

Development of DBIx::Perform was generously funded by Telecom
Engineering Associates of San Carlos, CA, a full-service 2-way radio
and telephony services company primarily serving public-sector
organizations in the SF Bay Area.  On the web at
http://www.tcomeng.com/ .  (do I sound like Frank Tavares yet?)

=head1 AUTHOR

Eric C. Weaver  E<lt>weav@sigma.netE<gt> 

=head1 COPYRIGHT AND LICENSE and other legal stuff

Copyright 2003 by Eric C. Weaver and 
Daryl D. Jones, Inc. (a California corporation).

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

INFORMIX and probably PERFORM is/are trademark(s) of
IBM these days.

=cut
