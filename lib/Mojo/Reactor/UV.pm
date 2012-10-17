package Mojo::Reactor::UV;
use Mojo::Base 'Mojo::Reactor::Poll';

use UV;
use Scalar::Util 'weaken';

my $UV;
my $running = 0;

sub DESTROY { undef $UV }

# We have to fall back to Mojo::Reactor::Poll, since EV is unique
sub new { $UV++ ? Mojo::Reactor::Poll->new : shift->SUPER::new }

sub is_running {
  return 0 unless $running;
  my $handles = UV::default_loop()->active_handles;
  $running=0 unless $handles;
  !!$handles;
}

sub one_tick { UV::run_once(); }

sub recurring { shift->_timer(1, @_) }

sub start {$running++; UV::run}

sub stop { UV::close($_) for (@{UV::handles()}); $running=0; }

sub timer { shift->_timer(0, @_) }

sub watch {
  my ($self, $handle, $read, $write) = @_;

  my $fd = fileno $handle;
  my $io = $self->{io}{$fd};
  my $mode;
  if ($read && $write) { $mode = UV::READABLE | UV::WRITABLE }
  elsif ($read)  { $mode = UV::READABLE }
  elsif ($write) { $mode = UV::WRITABLE }
  else           { delete $io->{watcher} }
  if (my $w = $io->{watcher}) { $w->set($fd, $mode) }
  elsif ($mode) {
    weaken $self;
    $io->{watcher} = UV::poll_start($fd, $mode, sub { $self->_io($fd, @_) });
  }

  return $self;
}

sub _io {
  my ($self, $fd, $w, $revents) = @_;
  my $io = $self->{io}{$fd};
  $self->_sandbox('Read', $io->{cb}, 0) if UV::READABLE &$revents;
  $self->_sandbox('Write', $io->{cb}, 1)
    if UV::WRITABLE &$revents && $self->{io}{$fd};
}

sub _timer {
  my ($self, $recurring, $after, $cb) = @_;
  $after ||= '0.0001';

  my $id = $self->SUPER::_timer(0, 0, $cb);
  weaken $self;
  $self->{timers}{$id}{watcher} = UV::timer_init();
  UV::timer_start(
    $self->{timers}{$id}{watcher},
    $after => ($recurring ? $after : 0) => sub {
      $self->_sandbox("Timer $id", $self->{timers}{$id}{cb});
      delete $self->{timers}{$id} unless $recurring;
    }
  );

  return $id;
}

1;

=head1 NAME

Mojo::Reactor::UV - Low level event reactor with libev support

=head1 SYNOPSIS

  use Mojo::Reactor::UV;

  # Watch if handle becomes readable or writable
  my $reactor = Mojo::Reactor::UV->new;
  $reactor->io($handle => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Handle is writable' : 'Handle is readable';
  });

  # Change to watching only if handle becomes writable
  $reactor->watch($handle, 0, 1);

  # Add a timer
  $reactor->timer(15 => sub {
    my $reactor = shift;
    $reactor->remove($handle);
    say 'Timeout!';
  });

  # Start reactor if necessary
  $reactor->start unless $reactor->is_running;

=head1 DESCRIPTION

L<Mojo::Reactor::UV> is a low level event reactor based on L<EV> (4.0+).

=head1 EVENTS

L<Mojo::Reactor::UV> inherits all events from L<Mojo::Reactor::Poll>.

=head1 METHODS

L<Mojo::Reactor::UV> inherits all methods from L<Mojo::Reactor::Poll> and
implements the following new ones.

=head2 C<new>

  my $reactor = Mojo::Reactor::UV->new;

Construct a new L<Mojo::Reactor::UV> object.

=head2 C<is_running>

  my $success = $reactor->is_running;

Check if reactor is running.

=head2 C<one_tick>

  $reactor->one_tick;

Run reactor until an event occurs or no events are being watched anymore. Note
that this method can recurse back into the reactor, so you need to be careful.

=head2 C<recurring>

  my $id = $reactor->recurring(0.25 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds.

=head2 C<start>

  $reactor->start;

Start watching for I/O and timer events, this will block until C<stop> is
called or no events are being watched anymore.

=head2 C<stop>

  $reactor->stop;

Stop watching for I/O and timer events.

=head2 C<timer>

  my $id = $reactor->timer(0.5 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds.

=head2 C<watch>

  $reactor = $reactor->watch($handle, $readable, $writable);

Change I/O events to watch handle for with C<true> and C<false> values. Note
that this method requires an active I/O watcher.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
