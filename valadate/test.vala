/*
 * Valadate - Unit testing library for GObject-based libraries.
 * Copyright (C) 2016  Chris Daley <chebizarro@gmail.com>
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
 * Authors:
 * 	Chris Daley <chebizarro@gmail.com>
 */
/**
 * The Test interface is implemented by TestCase and TestSuite.
 * It is the base interface for all runnable Tests.
 */
public interface Valadate.Test : Object {
		
	/**
	 * Runs the Tests and collects the results in a TestResult 
	 *
	 * @param result the TestResult object used to store the results of the Test
	 */
	public abstract void run (TestResult result);

	/**
	 * The name of the test
	 */
	public abstract string name { get; set; }

	/**
	 * Returns the number of tests that will be run by this test
	 */
	public abstract int count {get;}

	public abstract Test get_test(int index);

	public virtual TestIterator iterator() {
		return new TestIterator(this);
	}
	
	public class TestIterator {
		
		private Test test;
		private Test current;
		private int index = 0;
		
		public TestIterator(Test test) {
			this.test = test;
		}
		
		public Test get() {
			current = this.test.get_test(index);
			index++;
			return current;
		}

		public bool next() {
			if (index >= this.test.count)
				return false;
			return true;
		}

		public int size {
			get {
				return this.test.count;
			}
		}
	}
}
