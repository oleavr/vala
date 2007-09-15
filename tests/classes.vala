using GLib;

class SimpleClass {
	public int field;
}

class DerivedClass : SimpleClass {
}

public class PublicClass {
	public int field;
}

abstract class AbstractClass {
	public int field;
}

static class StaticClass {
}

class ClassWithCreationMethod {
	public ClassWithCreationMethod () {
		stdout.printf ("ClassWithCreationMethod\n");
	}

	public int field;
}

class ClassWithNamedCreationMethod {
	public ClassWithNamedCreationMethod.named () {
		stdout.printf ("ClassWithNamedCreationMethod\n");
	}

	public int field;
}

class SimpleGObjectClass : Object {
}

class DerivedGObjectClass : SimpleGObjectClass {
}

public class PublicGObjectClass : Object {
}

abstract class AbstractGObjectClass : Object {
}

class GObjectClassWithCreationMethod : Object {
	public GObjectClassWithCreationMethod () {
	}
}

class GObjectClassWithNamedCreationMethod : Object {
	public GObjectClassWithNamedCreationMethod.named () {
	}
}

static class ClassesTest {
	static int main (string[] args) {
		stdout.printf ("Classes Test:\n");

		stdout.printf ("new SimpleClass ()\n");
		var simple_class = new SimpleClass ();
		stdout.printf ("new DerivedClass ()\n");
		var derived_class = new DerivedClass ();
		stdout.printf ("new PublicClass ()\n");
		var public_class = new PublicClass ();
		stdout.printf ("new ClassWithCreationMethod ()\n");
		var class_with_creation_method = new ClassWithCreationMethod ();
		stdout.printf ("new ClassWithNamedCreationMethod ()\n");
		var class_with_named_creation_method = new ClassWithNamedCreationMethod.named ();

		stdout.printf ("new SimpleGObjectClass ()\n");
		var simple_gobject_class = new SimpleGObjectClass ();
		stdout.printf ("new DerivedGObjectClass ()\n");
		var derived_gobject_class = new DerivedGObjectClass ();
		stdout.printf ("new PublicGObjectClass ()\n");
		var public_gobject_class = new PublicGObjectClass ();
		stdout.printf ("new GObjectClassWithCreationMethod ()\n");
		var gobject_class_with_creation_method = new GObjectClassWithCreationMethod ();
		stdout.printf ("new GObjectClassWithNamedCreationMethod ()\n");
		var gobject_class_with_named_creation_method = new GObjectClassWithNamedCreationMethod.named ();

		stdout.printf ("new SimpleClass () { field = 1 }\n");
		simple_class = new SimpleClass () { field = 1 };
		stdout.printf ("simple_class.field = %d\n", simple_class.field);

		stdout.printf (".\n");

		return 0;
	}
}

