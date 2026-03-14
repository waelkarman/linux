#include <linux/syscalls.h>
#include <linux/uaccess.h>
#include <linux/printk.h> 

   SYSCALL_DEFINE1(sys_open_with_initial_comment,
       const char __user *, pathname)
   {
       char kernel_buf[256];
       long ret;

       ret = strncpy_from_user(kernel_buf, pathname, sizeof(kernel_buf) - 1);
       kernel_buf[ret] = '\0';

       pr_info("my_custom_syscall: path received = %s\n", kernel_buf);

       return 0;
   }