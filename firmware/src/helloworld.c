#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"

int main()
{
    init_platform();

    usleep(1000000);

    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("        M U R O S Y N C  -  P O C        \r\n");
    xil_printf("========================================\r\n");
    xil_printf(" FPGA   : XCAU15P\r\n");
    xil_printf(" CPU    : MicroBlaze\r\n");
    xil_printf(" Build  : Hello World\r\n");
    xil_printf("========================================\r\n");
    xil_printf("\r\n");

    for(;;)
    {
    	xil_printf("[MuroSync] alive...\r\n");
    	usleep(1000000);
    }

    cleanup_platform();
    return 0;
}
