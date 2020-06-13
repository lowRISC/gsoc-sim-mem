#include "VSimmem.h"
#include "verilated.h"
int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);

	VSimmem* top = new VSimmem;
	while (!Verilated::gotFinish())
	{

        printf("Coucou!");
	}

	delete top;
	exit(0);
}
