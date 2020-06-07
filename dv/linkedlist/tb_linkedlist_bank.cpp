#include "Vsimmem_linked_list_bank.h"
#include "verilated.h"
int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);

	Vsimmem_linked_list_bank* top = new Vsimmem_linked_list_bank;
	while (!Verilated::gotFinish())
	{
        printf("Coucou! Je teste la linkedlist bandk\n");
	}

	delete top;
	exit(0);
}
