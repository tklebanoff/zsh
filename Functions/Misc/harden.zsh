#!/bin/sh
# harden a link (convert it to a singly linked file)
cp $1 $1.foo
rm $1
mv $1.foo $1

