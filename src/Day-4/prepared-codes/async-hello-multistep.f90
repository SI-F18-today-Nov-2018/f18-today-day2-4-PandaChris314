! async-hello-2018.f90
!
! -- A Parallel "Hello World" program in Fortran 2018:
!    Image 1 asynchronously gets and prints greetings defined by every image.
!
! The program uses event post, query, and wait defined by a  Fortarn 2018.
program main
  use iso_fortran_env, only : event_type,output_unit
  implicit none

  character(len=96) :: greeting[*]
  type(event_type), allocatable :: greeting_ready(:)[:]
  type(event_type) :: ok_to_overwrite[*]
  integer :: step
  integer, parameter :: nsteps=4

  associate( me=>this_image(), ni=>num_images() )

    allocate(greeting_ready(ni)[*])

    do step=1,nsteps

      if (me/=1) then
        ! Wait for image 1 signal that it has the previous greeting
        if (step>1) event wait( ok_to_overwrite ) ! Atomically decrements my ok-to-write counter
        write(greeting,*) "Hello from image ",me," of ",ni," on step ",step
        ! Signal image 1 that a new greeting is ready for pickup:
        event post(greeting_ready(me)[1])              ! Atomically increments my event greeting-ready counter on image 1

      else

        write(greeting,*) "Hello from image ",me," of ",ni," on step ",step
        print *,greeting

        spin_query_work: block
          integer :: image,ready_count
          integer, save, allocatable :: previous_count(:)
          logical, dimension(2:ni) :: greeting_not_printed

          if (.not. allocated(previous_count)) allocate(previous_count(2:ni),source=0)

          greeting_not_printed=.true.

          spin: do while( any( greeting_not_printed  ) ) ! Loop until all greetings have been printed
            query: do image=2,ni             ! Atomically access each event's counter
              if (greeting_not_printed(image)) then      ! Print greetings that have not been printed during this step
                call event_query( greeting_ready(image), ready_count)
                work_if_ready: select case(ready_count-previous_count(image))
                  case(0) ! keep spinning until greeting is ready
                  case(1) ! event posted so get and print greeting
                    print *,greeting[image]
                    event post(ok_to_overwrite[image])
                    greeting_not_printed(image)=.false.
                    previous_count(image)=ready_count
                  case default
                    if (ready_count<0) error stop "compiler bug: negative event_query count"
                    error stop "multiple events happened since the last event query"
                end select work_if_ready
              end if
            end do query
          end do spin

        end block spin_query_work
      end if
    end do

  end associate

end program
