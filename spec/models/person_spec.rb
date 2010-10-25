#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'

describe Person do
  before do
    @user = Factory.create(:user)
    @user2 = Factory.create(:user)
    @person = Factory.create(:person)
    @aspect = @user.aspect(:name => "Dudes")
    @aspect2 = @user2.aspect(:name => "Abscence of Babes")
  end

  describe "validation" do
    describe "of associated profile" do
      it "fails if the profile isn't valid" do
        person = Factory.build(:person)
        person.should be_valid
        
        person.profile.update_attribute(:first_name, nil)
        person.profile.should_not be_valid
        person.should_not be_valid

        person.errors.count.should == 1
        person.errors.full_messages.first.should =~ /first name/i
      end
    end
  end

  describe '#diaspora_handle' do
    context 'local people' do
      it 'uses the pod config url to set the diaspora_handle' do
        @user.person.diaspora_handle.should == @user.username + "@" + APP_CONFIG[:terse_pod_url]
      end
    end

    context 'remote people' do
      it 'stores the diaspora_handle in the database' do
        @person.diaspora_handle.include?(APP_CONFIG[:terse_pod_url]).should be false
      end
    end
    describe 'validation' do
      it 'is unique' do
        person_two = Factory.build(:person, :url => @person.diaspora_handle)
        person_two.valid?.should be_false
      end

      it 'is case insensitive' do
        person_two = Factory.build(:person, :url => @person.diaspora_handle.upcase)
        person_two.valid?.should be_false
      end
    end
  end

  describe 'xml' do
    before do
      @xml = @person.to_xml.to_s
    end

    it 'should serialize to xml' do
      @xml.include?("person").should == true
    end

    it 'should have a profile in its xml' do
      @xml.include?("first_name").should == true

    end
  end

  it '#owns? posts' do
    person_message = Factory.create(:status_message, :person => @person)
    person_two =     Factory.create(:person)

    @person.owns?(person_message).should be true
    person_two.owns?(person_message).should be false
  end

  it "deletes all of a person's posts upon person deletion" do
    person = Factory.create(:person)

    status = Factory.create(:status_message, :person => person)
    Factory.create(:status_message, :person => @person)

    lambda {person.destroy}.should change(Post, :count).by(-1)
  end

  it "does not delete a person's comments on person deletion" do
    person = Factory.create(:person)

    status_message = Factory.create(:status_message, :person => @person)

    Factory.create(:comment, :person_id => person.id,  :text => "i love you",     :post => status_message)
    Factory.create(:comment, :person_id => @person.id, :text => "you are creepy", :post => status_message)
    
    lambda {person.destroy}.should_not change(Comment, :count)
  end

  describe "unfriending" do
    it 'should not delete an orphaned friend' do
      @user.activate_friend(@person, @aspect)

      lambda {@user.unfriend(@person)}.should_not change(Person, :count)
    end

    it 'should not delete an un-orphaned friend' do
      @user.activate_friend(@person, @aspect)
      @user2.activate_friend(@person, @aspect2)

      lambda {@user.unfriend(@person)}.should_not change(Person, :count)
    end
  end

  describe '#search' do
    before do
      @friend_one   = Factory.create(:person)
      @friend_two   = Factory.create(:person)
      @friend_three = Factory.create(:person)
      @friend_four  = Factory.create(:person)

      @friend_one.profile.first_name = "Robert"
      @friend_one.profile.last_name  = "Grimm"
      @friend_one.profile.save

      @friend_two.profile.first_name = "Eugene"
      @friend_two.profile.last_name  = "Weinstein"
      @friend_two.save

      @friend_three.profile.first_name = "Yevgeniy"
      @friend_three.profile.last_name  = "Dodis"
      @friend_three.save

      @friend_four.profile.first_name = "Casey"
      @friend_four.profile.last_name  = "Grippi"
      @friend_four.save
    end

    it 'should yield search results on partial names' do
      people = Person.search("Eu")
      people.include?(@friend_two).should   == true
      people.include?(@friend_one).should   == false
      people.include?(@friend_three).should == false
      people.include?(@friend_four).should  == false

      people = Person.search("wEi")
      people.include?(@friend_two).should   == true
      people.include?(@friend_one).should   == false
      people.include?(@friend_three).should == false
      people.include?(@friend_four).should  == false

      people = Person.search("gri")
      people.include?(@friend_one).should   == true
      people.include?(@friend_four).should  == true
      people.include?(@friend_two).should   == false
      people.include?(@friend_three).should == false
    end

    it 'should yield results on full names' do
      people = Person.search("Casey Grippi")
      people.should == [@friend_four]
    end
  end

  context 'people finders for webfinger' do
    let(:user) {Factory(:user)}
    let(:person) {Factory(:person)}

    describe '.by_account_identifier' do
      it 'should find a local users person' do
        p = Person.by_account_identifier(user.diaspora_handle)
        p.should == user.person
      end

      it 'should find remote users person' do
        p = Person.by_account_identifier(person.diaspora_handle)
        p.should == person
      end

      it 'should downcase and strip the diaspora_handle' do
        dh_upper = "    " + user.diaspora_handle.upcase + "   "
        Person.by_account_identifier(dh_upper).should == user.person
      end

      it "finds a local person with a mixed-case username" do
        user = Factory(:user, :username => "SaMaNtHa")
        person = Person.by_account_identifier(user.person.diaspora_handle)
        person.should == user.person
      end

      it "is case insensitive" do
        user1 = Factory(:user, :username => "SaMaNtHa")
        person = Person.by_account_identifier(user1.person.diaspora_handle.upcase)
        person.should == user1.person
      end

      it 'should only find people who are exact matches' do
        user = Factory(:user, :username => "SaMaNtHa")
        person = Factory(:person, :diaspora_handle => "tomtom@tom.joindiaspora.com")
        user.person.diaspora_handle = "tom@tom.joindiaspora.com"
        user.person.save
        Person.by_account_identifier("tom@tom.joindiaspora.com").diaspora_handle.should == "tom@tom.joindiaspora.com"
      end

      it 'should return nil if there is not an exact match' do
        pending "should check in the webfinger client"
        person = Factory(:person, :diaspora_handle => "tomtom@tom.joindiaspora.com")
        person1 = Factory(:person, :diaspora_handle => "tom@tom.joindiaspora.comm")
        #Person.by_webfinger("tom@tom.joindiaspora.com").should_be false 
        proc{ Person.by_webfinger("tom@tom.joindiaspora.com")}.should raise_error
      end


      it 'identifier should be a valid email' do
        pending "should check in the webfinger client"
        stub_success("joe.valid+email@my-address.com")
        Proc.new { 
          Person.by_account_identifier("joe.valid+email@my-address.com")
        }.should_not raise_error(RuntimeError, "Identifier is invalid")

        stub_success("not_a_@valid_email")
        Proc.new { 
          Person.by_account_identifer("not_a_@valid_email")
        }.should raise_error(RuntimeError, "Identifier is invalid")

      end

      it 'should not accept a port number' do
        pending "should check the webfinger client"
        stub_success("eviljoe@diaspora.local:3000")
        Proc.new { 
          Person.by_account_identifier('eviljoe@diaspora.local:3000')
        }.should raise_error(RuntimeError, "Identifier is invalid")
      end

    end

    describe '.local_by_account_identifier' do
      it 'should find local users people' do
        p = Person.local_by_account_identifier(user.diaspora_handle)
        p.should == user.person
      end

      it 'should not find a remote person' do
        p = Person.local_by_account_identifier(@person.diaspora_handle)
        p.should be nil
      end

      it 'should call .by_account_identifier' do
        Person.should_receive(:by_account_identifier)
        Person.local_by_account_identifier(@person.diaspora_handle)
      end
    end
  end
end
