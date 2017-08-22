/* valatemplate.vala
 *
 * Copyright (C) 2009-2010  Jürg Billeter
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
 * 	Jürg Billeter <j@bitron.ch>
 */


public class Vala.Template : Expression {
	private List<Expression> expression_list = new ArrayList<Expression> ();

	public Template (SourceReference? source_reference = null) {
		this.source_reference = source_reference;
	}

	public override void accept (CodeVisitor visitor) {
		visitor.visit_template (this);
	}

	public override void accept_children (CodeVisitor visitor) {
		foreach (var expr in expression_list) {
			expr.accept (visitor);
		}
	}

	public void add_expression (Expression expr) {
		expr.parent_node = this;
		expression_list.add (expr);
	}

	public List<Expression> get_expressions () {
		return expression_list;
	}

	public override bool is_pure () {
		return false;
	}

	public override bool check (CodeContext context) {
		if (checked) {
			return !error;
		}

		checked = true;

		foreach (var expr in expression_list) {
			if (!expr.check (context)) {
				error = true;
				continue;
			}
		}

		value_type = context.analyzer.string_type.copy ();
		value_type.value_owned = true;

		return !error;
	}
}

