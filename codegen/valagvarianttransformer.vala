/* valagvarianttransformer.vala
 *
 * Copyright (C) 2011  Luca Bruno
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Luca Bruno <lucabru@src.gnome.org>
 */

/**
 * Code visitor for transforming the code tree related to GVariant.
 */
public class Vala.GVariantTransformer : CodeTransformer {
	struct BasicTypeInfo {
		public unowned string signature;
		public unowned string type_name;
		public bool is_string;
	}

	const BasicTypeInfo[] basic_types = {
		{ "y", "byte", false },
		{ "b", "boolean", false },
		{ "n", "int16", false },
		{ "q", "uint16", false },
		{ "i", "int32", false },
		{ "u", "uint32", false },
		{ "x", "int64", false },
		{ "t", "uint64", false },
		{ "d", "double", false },
		{ "s", "string", true },
		{ "o", "object_path", true },
		{ "g", "signature", true }
	};

	CodeBuilder b;

	bool get_basic_type_info (string signature, out BasicTypeInfo basic_type) {
		foreach (BasicTypeInfo info in basic_types) {
			if (info.signature == signature) {
				basic_type = info;
				return true;
			}
		}
		basic_type = BasicTypeInfo ();
		return false;
	}

	Expression expression (string str) {
		return new Parser().parse_expression_string (str, b.source_reference);
	}

	Expression serialize_basic (BasicTypeInfo basic_type, Expression expr) {
		var new_call = (ObjectCreationExpression) expression (@"new GLib.Variant.$(basic_type.type_name)()");
		new_call.add_argument (expr);
		return new_call;
	}

	public static string? get_dbus_signature (Symbol symbol) {
		return symbol.get_attribute_string ("DBus", "signature");
	}

	static bool is_string_marshalled_enum (TypeSymbol? symbol) {
		if (symbol != null && symbol is Enum) {
			return symbol.get_attribute_bool ("DBus", "use_string_marshalling");
		}
		return false;
	}

	public static string? get_type_signature (DataType datatype, Symbol? symbol = null) {
		if (symbol != null) {
			string sig = get_dbus_signature (symbol);
			if (sig != null) {
				// allow overriding signature in attribute, used for raw GVariants
				return sig;
			}
		}

		var array_type = datatype as ArrayType;

		if (array_type != null) {
			string element_type_signature = get_type_signature (array_type.element_type);

			if (element_type_signature == null) {
				return null;
			}

			return string.nfill (array_type.rank, 'a') + element_type_signature;
		} else if (is_string_marshalled_enum (datatype.data_type)) {
			return "s";
		} else if (datatype.data_type != null) {
			string sig = datatype.data_type.get_attribute_string ("CCode", "type_signature");

			var st = datatype.data_type as Struct;
			var en = datatype.data_type as Enum;
			if (sig == null && st != null) {
				var str = new StringBuilder ();
				str.append_c ('(');
				foreach (Field f in st.get_fields ()) {
					if (f.binding == MemberBinding.INSTANCE) {
						str.append (get_type_signature (f.variable_type, f));
					}
				}
				str.append_c (')');
				sig = str.str;
			} else if (sig == null && en != null) {
				if (en.is_flags) {
					return "u";
				} else {
					return "i";
				}
			}

			var type_args = datatype.get_type_arguments ();
			if (sig != null && "%s" in sig && type_args.size > 0) {
				string element_sig = "";
				foreach (DataType type_arg in type_args) {
					var s = get_type_signature (type_arg);
					if (s != null) {
						element_sig += s;
					}
				}

				sig = sig.printf (element_sig);
			}

			if (sig == null &&
			    (datatype.data_type.get_full_name () == "GLib.UnixInputStream" ||
			     datatype.data_type.get_full_name () == "GLib.UnixOutputStream" ||
			     datatype.data_type.get_full_name () == "GLib.Socket")) {
				return "h";
			}

			return sig;
		} else {
			return null;
		}
	}

	DataType copy_type (DataType type, bool value_owned) {
		var ret = type.copy ();
		ret.value_owned = value_owned;
		return ret;
	}

	Expression serialize_array (ArrayType array_type, Expression array_expr) {
		string temp = b.add_temp_declaration (array_type, array_expr);

		string[] indices = new string[array_type.rank];
		for (int dim=1; dim <= array_type.rank; dim++) {
			indices[dim-1] = b.add_temp_declaration (null, new IntegerLiteral ("0"));
		}
		return serialize_array_dim (array_type, 1, indices, temp);
	}

	Expression serialize_array_dim (ArrayType array_type, int dim, string[] indices, string array_var) {
		var builderinit = expression (@"new GLib.VariantBuilder (new GLib.VariantType (\"$(get_type_signature (array_type))\"))");

		var builder = b.add_temp_declaration (null, builderinit);

		Expression length = expression (array_var+".length");
		if (array_type.rank > 1) {
			ElementAccess ea = new ElementAccess (length, b.source_reference);
			ea.append_index (new IntegerLiteral ((dim-1).to_string (), b.source_reference));
			length = ea;
		}

		var index = indices[dim-1];
		var forcond = new BinaryExpression (BinaryOperator.LESS_THAN, expression (index), length, b.source_reference);
		var foriter = new PostfixExpression (expression (index), true, b.source_reference);
		b.open_for (null, forcond, foriter);

		Expression element_variant;
		if (dim < array_type.rank) {
			element_variant = serialize_array_dim (array_type, dim + 1, indices, array_var);
		} else {
			var element_expr = new ElementAccess (expression (array_var), b.source_reference);
			for (int i=0; i < dim; i++) {
				element_expr.append_index (expression (indices[i]));
			}
			element_variant = serialize_expression (copy_type (array_type.element_type, false), element_expr);
		}

		var builder_add = (MethodCall) expression (builder+".add_value ()");
		builder_add.add_argument (element_variant);
		b.add_expression (builder_add);
		b.close ();

		return (MethodCall) expression (builder+".end ()");
	}

	Expression serialize_struct (Struct st, Expression expr) {
		string temp = b.add_temp_declaration (expr.value_type, expr);

		var builderinit = expression ("new GLib.VariantBuilder (GLib.VariantType.TUPLE)");
		var builder = b.add_temp_declaration (null, builderinit);

		bool field_found = false;

		foreach (Field f in st.get_fields ()) {
			if (f.binding != MemberBinding.INSTANCE) {
				continue;
			}

			field_found = true;

			var serialized_field = serialize_expression (copy_type (f.variable_type, false), expression (@"$temp.$(f.name)"));
			MethodCall call = (MethodCall) expression (@"$builder.add_value ()");
			call.add_argument (serialized_field);
			b.add_expression (call);
		}

		if (!field_found) {
			return null;
		}

		return expression (@"$builder.end ()");
	}

	Expression? serialize_expression (DataType type, Expression expr) {
		if (type.data_type == context.analyzer.gvariant_type.data_type) {
			return expr;
		}

		BasicTypeInfo basic_type;
		Expression result = null;
		if (get_basic_type_info (get_type_signature (type), out basic_type)) {
			result = serialize_basic (basic_type, expr);
		} else if (type is ArrayType) {
			result = serialize_array ((ArrayType) type, expr);
		} else if (type.data_type is Struct) {
			result = serialize_struct ((Struct) type.data_type, expr);
		}
		return result;
	}

	public override void visit_expression (Expression expr) {
		base.visit_expression (expr);

		if (!(context.profile == Profile.GOBJECT && expr.target_type != null && expr.target_type.data_type == context.analyzer.gvariant_type.data_type && !(expr.value_type is NullType) && expr.value_type.data_type != context.analyzer.gvariant_type.data_type)) {
			// no implicit gvariant boxing
			return;
		}

		b = new CodeBuilder (context, expr.parent_statement, expr.source_reference);
		var old_parent_node = expr.parent_node;
		var target_type = expr.target_type.copy ();

		Expression result = serialize_expression (expr.value_type, expr);

		result.target_type = target_type;
		context.analyzer.replaced_nodes.add (expr);
		old_parent_node.replace_expression (expr, result);
		foreach (var node in b.check_nodes) {
			check (node);
		}
		check (result);
	}
}
