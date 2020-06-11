#include "Vsimmem_linkedlist_bank.h"
#include "verilated.h"

int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);

	Vsimmem_linkedlist_bank* top = new Vsimmem_linkedlist_bank;
	while (!Verilated::gotFinish())
	{

        printf("Alright it works!\n");
	}

	delete top;
	exit(0);
}

