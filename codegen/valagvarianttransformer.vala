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

	Statement current_statement;
	Block current_block;

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

	MemberAccess member_access (string symbol_string, CodeNode node) {
		MemberAccess? ma = null;
		bool first = true;
		foreach (unowned string s in symbol_string.substring(1).split (".")) {
			if (first) {
				ma = new MemberAccess (ma, symbol_string[0].to_string()+s, node.source_reference);
				first = false;
			} else {
				ma = new MemberAccess (ma, s, node.source_reference);
			}
		}
		return ma;
	}

	Expression serialize_basic (BasicTypeInfo basic_type, Expression expr) {
		var new_call = new ObjectCreationExpression (member_access ("GLib.Variant." + basic_type.type_name, expr), expr.source_reference);
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

	Expression serialize_array (ArrayType array_type, Expression array_expr) {
		LocalVariable temp = new LocalVariable (array_type, array_expr.get_temp_name (), array_expr, array_expr.source_reference);
		var decl = new DeclarationStatement (temp, array_expr.source_reference);
		context.analyzer.get_insert_block (current_statement).insert_before (current_statement, decl);
		check (decl);

		LocalVariable[] indices = new LocalVariable[array_type.rank];
		for (int dim=1; dim <= array_type.rank; dim++) {
			var index = new LocalVariable (null, array_expr.get_temp_name (), new IntegerLiteral ("0"), array_expr.source_reference);
			decl = new DeclarationStatement (index, array_expr.source_reference);
			context.analyzer.get_insert_block (current_statement).insert_before (current_statement, decl);
			check (decl);
			indices[dim-1] = index;
		}
		return serialize_array_dim (array_type, 1, indices, temp);
	}

	Expression serialize_array_dim (ArrayType array_type, int dim, LocalVariable[] indices, LocalVariable array_var) {
		var gvariant_type = new ObjectCreationExpression (member_access ("GLib.VariantType", array_var), array_var.source_reference);
		gvariant_type.add_argument (new StringLiteral ("\""+get_type_signature (array_type)+"\""));

		var builderinit = new ObjectCreationExpression (member_access ("GLib.VariantBuilder", array_var), array_var.source_reference);
		builderinit.add_argument (gvariant_type);

		var builder = new LocalVariable (null, array_var.get_temp_name (), builderinit, array_var.source_reference);
		var decl = new DeclarationStatement (builder, array_var.source_reference);
		context.analyzer.get_insert_block (current_statement).insert_before (current_statement, decl);
		check (decl);

		Expression length = member_access (array_var.name+".length", array_var);
		if (array_type.rank > 1) {
			ElementAccess ea = new ElementAccess (length, array_var.source_reference);
			ea.append_index (new IntegerLiteral ((dim-1).to_string (), array_var.source_reference));
			length = ea;
		}

		var index = indices[dim-1];
		var forcond = new BinaryExpression (BinaryOperator.LESS_THAN, member_access (index.name, array_var), length, array_var.source_reference);
		var foriter = new PostfixExpression (member_access (index.name, array_var), true, array_var.source_reference);
		var forbody = new Block (array_var.source_reference);
		var old_block = current_block;
		current_block = forbody;

		Expression element_variant;
		if (dim < array_type.rank) {
			element_variant = serialize_array_dim (array_type, dim + 1, indices, array_var);
		} else {
			var element_expr = new ElementAccess (member_access (array_var.name, array_var), array_var.source_reference);
			for (int i=0; i < dim; i++) {
				element_expr.append_index (member_access (indices[i].name, array_var));
			}
			element_variant = serialize_expression (array_type.element_type, element_expr);
		}
		current_block = old_block;

		var builder_add = new MethodCall (member_access (builder.name+".add_value", array_var), array_var.source_reference);
		builder_add.add_argument (element_variant);
		forbody.add_statement (new ExpressionStatement (builder_add, array_var.source_reference));

		var forstmt = new ForStatement (forcond, forbody, array_var.source_reference);
		forstmt.add_iterator (foriter);
		if (dim == 1) {
			context.analyzer.get_current_block (current_statement).insert_before (current_statement, forstmt);
			check (forstmt);
		} else {
			current_block.add_statement (forstmt);
		}

		var builder_end = new MethodCall (member_access (builder.name+".end", array_var), array_var.source_reference);
		return builder_end;
	}

	Expression? serialize_expression (DataType type, Expression expr) {
		BasicTypeInfo basic_type;
		Expression result = null;
		if (get_basic_type_info (get_type_signature (type), out basic_type)) {
			result = serialize_basic (basic_type, expr);
		} else if (expr.value_type is ArrayType) {
			result = serialize_array ((ArrayType) expr.value_type, expr);
		}
		return result;
	}

	public override void visit_expression (Expression expr) {
		base.visit_expression (expr);

		if (!(context.profile == Profile.GOBJECT && expr.target_type != null && expr.target_type.data_type == context.analyzer.gvariant_type.data_type && !(expr.value_type is NullType) && expr.value_type.data_type != context.analyzer.gvariant_type.data_type)) {
			// no implicit gvariant boxing
			return;
		}

		current_statement = get_current_statement (expr);
		var old_parent_node = expr.parent_node;
		var target_type = expr.target_type.copy ();

		current_block = context.analyzer.get_current_block (current_statement);
		Expression result = serialize_expression (expr.value_type, expr);

		result.target_type = target_type;
		old_parent_node.replace_expression (expr, result);
		check (result);
	}

	Statement get_current_statement (CodeNode node) {
		while (!(node is Statement)) {
			node = node.parent_node;
		}
		return (Statement) node;
	}
}
