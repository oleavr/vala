using GLib;

class Maman.Bar {
	static int main (int argc, string[] argv) {
		stdout.printf ("For Test: 1");

		int i;
		for (i = 2; i < 7; i++) {
			stdout.printf (" %d", i);
		}
		
		stdout.printf (" 7\n");

		return 0;
	}
}
