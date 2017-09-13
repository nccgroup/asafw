
* Atm we are rooting the asa*.bin with asafw when we want to use it to attach gdb in asadbg
  Then at boot we are modifying the lina_monitor command line to attach gdb from the root shell
  (automatically using asadbg). It would be cleaner and quicker to just enable gdb in the filesystem
  and not have any root shell at boot at all. 
  Another way of doing it would be to keep the root shell at boot and only use these for both booting
  with the debugger or without debugger. The advantage is that if we customised one .bin to have a debug
  shell, and other stuff, we don't have to generate 2 .bin but instead we rely on only one for both
  debugging/non-debugging it. Note that it has a drawback though. It is that it takes a bit longer to
  attach gdb when the root shell is enabled at boot than if it directly waits for gdb to connect
  See asadbg as well.

* in lina.py, we could use aaa_admin_authenticate() arguments (2nd is the SSH login, 3rd
  is the SSH password) to pass the IP/port to use for the reverse shell
  but this is maybe over complicated since we won't need to patch it several
  times for our debugging environment anyway